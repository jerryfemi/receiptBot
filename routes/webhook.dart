// ignore: duplicate_ignore
// ignore: lines_longer_than_80_chars
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:receipt_bot/config/app_config.dart';
import 'package:receipt_bot/handlers/handlers.dart';
import 'package:receipt_bot/handlers/stats_handler.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/routing/message_router.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/flutterwave_service.dart';
import 'package:receipt_bot/services/gemini_service.dart';
import 'package:receipt_bot/services/paystack_service.dart';
import 'package:receipt_bot/services/pdf_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/country_utils.dart';
import 'package:receipt_bot/utils/log.dart';
import 'package:receipt_bot/utils/meta_signature.dart';

// Configuration
final String _verifyToken = AppConfig.instance.verifyToken;
final String _whatsappToken = AppConfig.instance.whatsappToken;
final String _phoneNumberId = AppConfig.instance.phoneNumberId;
final String _projectId = AppConfig.instance.googleProjectId;
final String _geminiApiKey = AppConfig.instance.geminiApiKey;
// App Secret from Meta (App settings > Basic). Used to check that webhook
// requests really come from Meta.
final String _metaAppSecret = AppConfig.instance.metaAppSecret;

/// Thread-safe service holder using Completer pattern.
/// Prevents race conditions during concurrent request initialization.
class _ServiceHolder {
  static final _ServiceHolder _instance = _ServiceHolder._internal();
  factory _ServiceHolder() => _instance;
  _ServiceHolder._internal();

  Completer<void>? _initCompleter;
  bool _isInitialized = false;

  // Core services
  late final FirestoreService firestoreService;
  late final GeminiService geminiService;
  late final PdfService pdfService;
  late final PaystackService paystackService;
  late final FlutterwaveService flutterwaveService;
  late final WhatsAppService whatsappService;

  // Handlers
  late final OnboardingHandler onboardingHandler;
  late final SettingsHandler settingsHandler;
  late final SubscriptionHandler subscriptionHandler;
  late final ReceiptHandler receiptHandler;
  late final StatsHandler statsHandler;
  late final MessageRouter messageRouter;

  /// Thread-safe initialization. Only the first caller initializes;
  /// subsequent callers wait on the same Completer.
  Future<void> ensureInitialized() async {
    if (_isInitialized) return;

    if (_initCompleter != null) {
      // Another request is initializing - wait for it
      await _initCompleter!.future;
      return;
    }

    // First caller - start initialization
    _initCompleter = Completer<void>();

    try {
      // Initialize services
      firestoreService = FirestoreService(projectId: _projectId);
      await firestoreService.initialize();

      geminiService = GeminiService(apiKey: _geminiApiKey);
      pdfService = PdfService();
      paystackService = PaystackService();
      flutterwaveService = FlutterwaveService();
      whatsappService = WhatsAppService(
        token: _whatsappToken,
        phoneNumberId: _phoneNumberId,
      );

      // Initialize handlers (depend on services)
      onboardingHandler = OnboardingHandler(
        firestoreService: firestoreService,
        whatsappService: whatsappService,
      );
      settingsHandler = SettingsHandler(
        firestoreService: firestoreService,
        whatsappService: whatsappService,
        geminiService: geminiService,
      );
      subscriptionHandler = SubscriptionHandler(
        firestoreService: firestoreService,
        whatsappService: whatsappService,
        paystackService: paystackService,
        flutterwaveService: flutterwaveService,
        pdfService: pdfService,
      );
      receiptHandler = ReceiptHandler(
        firestoreService: firestoreService,
        whatsappService: whatsappService,
        geminiService: geminiService,
        pdfService: pdfService,
        settingsHandler: settingsHandler,
        subscriptionHandler: subscriptionHandler,
      );
      statsHandler = StatsHandler(
        firestoreService,
        whatsappService,
        geminiService,
      );

      messageRouter = MessageRouter(
        firestoreService: firestoreService,
        onboardingHandler: onboardingHandler,
        settingsHandler: settingsHandler,
        receiptHandler: receiptHandler,
        subscriptionHandler: subscriptionHandler,
        statsHandler: statsHandler,
        geminiService: geminiService,
        whatsappService: whatsappService,
      );

      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null; // Allow retry on next request
      rethrow;
    }
  }
}

/// Simple in-memory idempotency cache for processed message IDs.
/// Prevents duplicate processing when WhatsApp retries webhooks.
class _IdempotencyCache {
  static final _IdempotencyCache _instance = _IdempotencyCache._internal();
  factory _IdempotencyCache() => _instance;
  _IdempotencyCache._internal();

  final Map<String, DateTime> _processedIds = {};
  static const Duration _ttl = Duration(minutes: 5);
  static const int _maxSize = 1000;

  /// Returns true if this message was already processed.
  bool isDuplicate(String messageId) {
    _cleanup();
    return _processedIds.containsKey(messageId);
  }

  /// Marks a message as processed.
  void markProcessed(String messageId) {
    _cleanup();
    _processedIds[messageId] = DateTime.now();
  }

  /// Remove expired entries to prevent memory growth.
  void _cleanup() {
    if (_processedIds.length > _maxSize) {
      final now = DateTime.now();
      _processedIds
          .removeWhere((_, timestamp) => now.difference(timestamp) > _ttl);
    }
  }
}

// Global singleton instances
final _services = _ServiceHolder();
final _idempotencyCache = _IdempotencyCache();

/// Helper to ensure services are initialized when called from other webhook handlers.
Future<void> initializeServicesForExternalWebhooks() =>
    _services.ensureInitialized();

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;

  // 1. WhatsApp Verification (GET)
  if (request.method == HttpMethod.get) {
    final params = request.uri.queryParameters;
    if (params['hub.mode'] == 'subscribe' &&
        params['hub.verify_token'] == _verifyToken) {
      Log.info('webhook', 'Webhook verified!');
      return Response(body: params['hub.challenge']);
    }
    return Response(statusCode: 403, body: 'Verification failed');
  }

  // 2. Initialize services (thread-safe, only happens once)
  try {
    await _services.ensureInitialized();
  } catch (e) {
    Log.error('webhook', 'Service initialization failed: $e');
    return Response(statusCode: 500, body: 'Service unavailable');
  }

  // 3. Handle Messages (POST)
  if (request.method == HttpMethod.post) {
    final body = await request.body();

    // Reject anything that wasn't signed by Meta with our App Secret.
    if (!MetaSignature.isValid(
      rawBody: body,
      header: request.headers[MetaSignature.headerName],
      appSecret: _metaAppSecret,
    )) {
      if (_metaAppSecret.isEmpty) {
        Log.warn('webhook',
            'META_APP_SECRET is not set - rejecting webhook request.');
      } else {
        Log.warn(
            'webhook', 'Rejected webhook request with an invalid signature.');
      }
      return Response(statusCode: 401, body: 'Invalid signature');
    }

    try {
      final json = jsonDecode(body);
      final entry = json['entry'][0];
      final changes = entry['changes'][0]['value'];

      if (changes['messages'] != null) {
        final message = changes['messages'][0] as Map<String, dynamic>;
        final messageId = message['id'] as String?;

        // Idempotency check - prevent duplicate processing on WhatsApp retries
        if (messageId != null && _idempotencyCache.isDuplicate(messageId)) {
          Log.info(
              'webhook', 'Duplicate message detected: $messageId - skipping');
          return Response(body: 'EVENT_RECEIVED');
        }
        if (messageId != null) {
          _idempotencyCache.markProcessed(messageId);
        }

        // Answer Meta straight away and do the slow work (AI, PDF) in the
        // background. If we made Meta wait, it would assume delivery failed
        // and send the same message again.
        unawaited(_processMessage(message));
      }
    } catch (e) {
      Log.error('webhook', 'Error parsing webhook payload: $e');
    }

    return Response(body: 'EVENT_RECEIVED');
  }

  return Response(statusCode: 404);
}

/// Handles one incoming WhatsApp message after Meta has been answered.
Future<void> _processMessage(Map<String, dynamic> message) async {
  final from = message['from'] as String;

  // Let the user know straight away that the bot got their message.
  final messageId = message['id'] as String?;
  if (messageId != null) {
    unawaited(
      _services.whatsappService.showTyping(messageId).catchError((Object e) {
        Log.warn('webhook', 'Could not show typing indicator: $e');
        return false;
      }),
    );
  }

  try {
    final type = message['type'] as String;

    var text = '';
    if (type == 'text') {
      text = message['text']['body'] as String;
    } else if (type == 'image') {
      text =
          (message['image']?['caption'] ?? message['caption'] ?? '') as String;
    } else if (type == 'interactive') {
      final interactive = message['interactive'] as Map<String, dynamic>;
      if (interactive['type'] == 'button_reply') {
        text = interactive['button_reply']['id'] as String;
      } else if (interactive['type'] == 'list_reply') {
        text = interactive['list_reply']['id'] as String;
      }
    }

    var profile = await _services.firestoreService.getProfile(from);
    if (profile == null) {
      Log.info('webhook', 'Creating new user profile...');
      final currencyInfo = CountryUtils.getCurrencyFromPhone(from);
      profile = BusinessProfile(
        phoneNumber: from,
        currencyCode: currencyInfo.code,
        currencySymbol: currencyInfo.symbol,
      );
    }

    await _services.messageRouter.routeMessage(
      phoneNumber: from,
      text: text,
      type: type,
      messageData: message,
      profile: profile,
    );
  } catch (e, stack) {
    Log.error('webhook', 'Background processing error for $from: $e\n$stack');
  }
}

/// Helper function to automatically generate and send a Proof of Payment
/// receipt using the Signature layout when a user successfully subscribes.
Future<void> generateAndSendSubscriptionReceipt(
  String phoneNumber,
  BusinessProfile profile,
  String planName,
  num amountPaid,
  String currencyCode,
) async {
  try {
    Log.info('webhook', 'Generating Subscription Receipt for $phoneNumber...');

    // 1. Create a synthetic Transaction representing the subscription
    final subscriptionItem = ReceiptItem(
      description: '1x Premium Subscription ($planName)',
      amount: amountPaid.toDouble(),
      quantity: 1,
    );

    final transaction = Transaction(
      date: DateTime.now(),
      items: [subscriptionItem],
      totalAmount: amountPaid.toDouble(),
      type: TransactionType.receipt,
      customerName: profile.businessName ?? 'Valued Customer',
      customerPhone: phoneNumber,
    );

    final resolvedCurrencySymbol = currencyCode == 'NGN'
        ? '₦'
        : currencyCode == 'GBP'
            ? '£'
            : currencyCode == 'EUR'
                ? '€'
                : r'$';

    final botOrg = Organization(
      id: 'bot_org',
      businessName: 'ReceiptBot Inc.',
      businessAddress: 'Global Digital Service',
      displayPhoneNumber: '+2348021146844', // Or standard bot support number
      logoUrl: null, // TODO: add the bot's own logo to public/logos
      inviteCode: '',
      currencyCode: currencyCode,
      currencySymbol: resolvedCurrencySymbol,
    );

    // 3. Generate the PDF
    // We use layoutIndex 1 (Signature Layout) and themeIndex 0 (Classic)
    final pdfBytes = await _services.pdfService.generateReceipt(
      profile,
      transaction,
      themeIndex: 0,
      layoutIndex: 1,
      org: botOrg,
    );

    // 4. Send via WhatsApp (uploaded straight to WhatsApp's media store)
    final fileName =
        'proof_of_payment_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await _services.whatsappService.sendDocumentBytes(
      phoneNumber,
      pdfBytes,
      fileName,
    );
    Log.info(
        'webhook', 'Subscription Receipt sent successfully to $phoneNumber');
  } catch (e) {
    Log.error('webhook',
        'Error generating subscription receipt for $phoneNumber: $e');
  }
}
