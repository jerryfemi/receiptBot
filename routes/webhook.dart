// ignore: duplicate_ignore
// ignore: lines_longer_than_80_chars
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
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

// Configuration
final String _verifyToken = Platform.environment['VERIFY_TOKEN'] ?? '';
final String _whatsappToken = Platform.environment['WHATSAPP_TOKEN'] ?? '';
final String _phoneNumberId = Platform.environment['PHONE_NUMBER_ID'] ?? '';
final String _projectId =
    Platform.environment['GOOGLE_PROJECT_ID'] ?? 'invoicemaker-b3876';
final String _geminiApiKey = Platform.environment['GEMINI_API_KEY'] ?? '';

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
  print('HIT!');
  final request = context.request;

  // 1. WhatsApp Verification (GET)
  if (request.method == HttpMethod.get) {
    final params = request.uri.queryParameters;
    if (params['hub.mode'] == 'subscribe' &&
        params['hub.verify_token'] == _verifyToken) {
      print('Webhook verified!');
      return Response(body: params['hub.challenge']);
    }
    return Response(statusCode: 403, body: 'Verification failed');
  }

  // 2. Initialize services (thread-safe, only happens once)
  try {
    await _services.ensureInitialized();
  } catch (e) {
    print('Service initialization failed: $e');
    return Response(statusCode: 500, body: 'Service unavailable');
  }

  // 3. Handle Messages (POST)
  if (request.method == HttpMethod.post) {
    print('Received POST request');
    final body = await request.body();
    final json = jsonDecode(body);

    try {
      final entry = json['entry'][0];
      final changes = entry['changes'][0]['value'];

      if (changes['messages'] != null) {
        final message = changes['messages'][0];
        final messageId = message['id'] as String?;
        final from = message['from'] as String;
        final type = message['type'] as String;

        // Idempotency check - prevent duplicate processing on WhatsApp retries
        if (messageId != null && _idempotencyCache.isDuplicate(messageId)) {
          print('Duplicate message detected: $messageId - skipping');
          return Response(body: 'EVENT_RECEIVED');
        }
        if (messageId != null) {
          _idempotencyCache.markProcessed(messageId);
        }

        var text = '';
        if (type == 'text') {
          text = message['text']['body'] as String;
        } else if (type == 'image') {
          text = (message['caption'] ?? '') as String;
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
          print('Creating new user profile...');
          final currencyInfo = CountryUtils.getCurrencyFromPhone(from);
          profile = BusinessProfile(
            phoneNumber: from,
            currencyCode: currencyInfo.code,
            currencySymbol: currencyInfo.symbol,
          );
        }

        await _services.messageRouter
            .routeMessage(
              phoneNumber: from,
              text: text,
              type: type,
              messageData: message as Map<String, dynamic>,
              profile: profile,
            )
            .catchError((e) => print('Background processing error: $e'));
      }
    } catch (e) {
      print('Error parsing webhook payload: $e');
    }

    return Response(body: 'EVENT_RECEIVED');
  }

  return Response(statusCode: 404);
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
    print('Generating Subscription Receipt for $phoneNumber...');

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
      logoUrl:
          'https://firebasestorage.googleapis.com/v0/b/invoicemaker-b3876.appspot.com/o/receipts%2Fbot_logo.png?alt=media',
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

    // 4. Upload to Firebase Storage
    final fileName =
        'proof_of_payment_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final pdfUrl = await _services.firestoreService.uploadFile(
      'receipts/$phoneNumber/$fileName',
      pdfBytes,
      'application/pdf',
    );

    // 5. Send via WhatsApp
    await _services.whatsappService.sendDocument(
      phoneNumber,
      pdfUrl,
      fileName,
    );
    print('Subscription Receipt sent successfully to $phoneNumber');
  } catch (e) {
    print('Error generating subscription receipt for $phoneNumber: $e');
  }
}
