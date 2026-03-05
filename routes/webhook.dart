// ignore: duplicate_ignore
// ignore: lines_longer_than_80_chars
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/handlers/handlers.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/gemini_service.dart';
import 'package:receipt_bot/services/lemon_squeezy_service.dart';
import 'package:receipt_bot/services/paystack_service.dart';
import 'package:receipt_bot/services/pdf_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/constants.dart';

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
  late final LemonSqueezyService lemonSqueezyService;
  late final WhatsAppService whatsappService;

  // Handlers
  late final OnboardingHandler onboardingHandler;
  late final SettingsHandler settingsHandler;
  late final SubscriptionHandler subscriptionHandler;
  late final ReceiptHandler receiptHandler;

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
      lemonSqueezyService = LemonSqueezyService();
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
        lemonSqueezyService: lemonSqueezyService,
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

        _handleMessage(from, text, type, message as Map<String, dynamic>)
            .catchError((e) => print('Background processing error: $e'));
      }
    } catch (e) {
      print('Error parsing webhook payload: $e');
    }

    return Response(body: 'EVENT_RECEIVED');
  }

  return Response(statusCode: 404);
}

Future<void> _handleMessage(
  String from,
  String text,
  String type,
  Map<String, dynamic> messageData,
) async {
  print('--- Handling message from $from ---');
  print('Text: $text');

  try {
    // 1. Get Profile
    var profile = await _services.firestoreService.getProfile(from);

    // If no profile, create new one
    if (profile == null) {
      print('Creating new user profile...');

      // Determine default currency from phone number
      final currencyInfo = CountryUtils.getCurrencyFromPhone(from);

      profile = BusinessProfile(
        phoneNumber: from,
        currencyCode: currencyInfo.code,
        currencySymbol: currencyInfo.symbol,
      );
    }

    // 2. State Machine
    switch (profile.status ?? OnboardingStatus.new_user) {
      case OnboardingStatus.new_user:
        await _services.onboardingHandler.handleNewUser(from);
        break;

      case OnboardingStatus.awaiting_setup_choice:
        await _services.onboardingHandler.handleSetupChoice(from, text);
        break;

      case OnboardingStatus.awaiting_invite_code:
        await _services.onboardingHandler.handleInviteCode(from, text);
        break;

      case OnboardingStatus.awaiting_address:
        // Here `text` is the businessName provided
        await _services.onboardingHandler.handleBusinessName(from, text);
        break;

      case OnboardingStatus.awaiting_phone:
        await _services.onboardingHandler
            .handleBusinessAddress(from, text, profile);
        break;

      case OnboardingStatus.active:
        await _handleActiveUser(from, text, type, messageData, profile);
        break;
    }
  } catch (e) {
    print('Error in _handleMessage: $e');
    // If we fail outside the state machine (e.g. Firestore error)
    await _services.whatsappService.sendMessage(from, 'System Error: $e');
  }
}

Future<void> _handleActiveUser(
  String from,
  String text,
  String type,
  Map<String, dynamic> messageData,
  BusinessProfile profile,
) async {
  // 1. IMAGE HANDLING
  if (type == 'image') {
    // A. Priority: Check if we are in a specific flow that needs an image (e.g. Logo Upload)
    if (profile.currentAction == UserAction.editLogo) {
      // Let the switch statement handle it below
    }
    // B. Otherwise: Default to Image Scanning (Receipt Parsing)
    else {
      if (!(await _services.subscriptionHandler
          .checkFreemiumLimit(from, profile))) {
        return;
      }

      await _services.whatsappService.sendMessage(from, "Scanning image... 🔎");

      try {
        // A. Get the image from WhatsApp
        final imageId = messageData['image']['id'] as String;
        final url = await _services.whatsappService.getMediaUrl(imageId);
        // Note: downloadFileBytes returns List<int>, need to convert to Uint8List
        final imageBytesList =
            await _services.whatsappService.downloadFileBytes(url);
        final imageBytes = Uint8List.fromList(imageBytesList);

        // B. Send to Gemini Vision
        final transaction = await _services.geminiService.parseImageTransaction(
          imageBytes,
          currencySymbol: profile.currencySymbol,
          currencyCode: profile.currencyCode,
        );

        // C. Save & Ask for Theme (Same as text flow)
        await _services.firestoreService.updateProfileData(from, {
          'pendingTransaction': jsonEncode(transaction.toJson()),
          'currentAction': UserAction.selectTheme.name
        });

        await _services.whatsappService.sendInteractiveButtons(
          from,
          "I found ${transaction.items.length} items totaling ${profile.currencySymbol}${transaction.totalAmount}!\n\nSelect a style:",
          [
            {'id': '1', 'title': 'Classic'},
            {'id': '2', 'title': 'Beige'},
            {'id': '3', 'title': 'Blue'},
          ],
        );
      } catch (e) {
        print("Image Scan Error: $e");
        if (e.toString().contains('GEMINI_BUSY')) {
          await _services.whatsappService.sendMessage(from,
              "Google's AI servers are currently taking a quick nap! 😴 Please wait a minute and try sending your receipt image again.");
        } else {
          await _services.whatsappService.sendMessage(from,
              "⚠️ I couldn't read that image clearly.\n\n*Tips for better results:*\n• Ensure text is clearly visible\n• Keep the image upright (not rotated)\n• Use good lighting, avoid shadows\n• Crop to just the receipt/list\n\nOr type the details manually!");
        }
      }
      return; // Stop here if we scanned
    }
  }

  // 2. TEXT & INTERACTIVE COMMANDS (Global)
  if (type == 'text' || type == 'interactive') {
    final lower = text.toLowerCase().trim();

    // Global Command Handler
    final isHandled = await _handleGlobalCommands(from, lower, text, profile);
    if (isHandled) return;
  }

  // 4. Handle Current Action (Remaining actions from the original switch)
  switch (profile.currentAction ?? UserAction.idle) {
    case UserAction.createReceipt:
      await _services.receiptHandler
          .processReceiptResult(from, text, profile, isInvoice: false);
      break;
    case UserAction.createInvoice:
      await _services.receiptHandler
          .processReceiptResult(from, text, profile, isInvoice: true);
      break;
    case UserAction.selectLayout:
      await _services.receiptHandler.handleLayoutSelection(from, text, profile);
      break;
    case UserAction.selectingSubscriptionPlan:
      await _services.subscriptionHandler
          .handlePlanSelection(from, text, profile);
      break;

    case UserAction.awaitingEmailForUpgrade:
      await _services.subscriptionHandler
          .handleEmailForUpgrade(from, text, profile);
      break;
    case UserAction.removeTeamMember:
      await _services.settingsHandler.handleRemoveTeamMember(from, text);
      break;
    case UserAction.confirmRemoveTeamMember:
      await _services.settingsHandler.handleConfirmRemoveTeamMember(from, text);
      break;

    case UserAction.editProfileMenu:
      await _services.settingsHandler
          .handleEditProfileMenuSelection(from, text, profile);
      break;

    case UserAction.selectCurrency:
      await _services.settingsHandler
          .handleCurrencySelection(from, text, profile);
      break;

    case UserAction.editBankDetails:
      await _services.settingsHandler
          .handleEditBankDetails(from, text, profile);
      break;

    case UserAction.awaitingInvoiceBankDetails:
      await _services.receiptHandler
          .handleInvoiceBankDetails(from, text, profile);
      break;

    case UserAction.selectTheme:
      await _services.receiptHandler.handleThemeSelection(from, text, profile);
      break;

    case UserAction.editName:
      await _services.settingsHandler.handleEditName(from, text, type, profile);
      break;

    case UserAction.editPhone:
      await _services.settingsHandler
          .handleEditPhone(from, text, type, profile);
      break;

    case UserAction.editAddress:
      await _services.settingsHandler
          .handleEditAddress(from, text, type, profile);
      break;

    case UserAction.editLogo:
      await _services.settingsHandler
          .handleEditLogo(from, type, messageData, profile);
      break;

    case UserAction.idle:
      // CONVERSATIONAL ROUTER

      try {
        final intentResult =
            await _services.geminiService.determineUserIntent(text);

        switch (intentResult.type) {
          case UserIntent.chat:
            if (intentResult.response != null) {
              await _services.whatsappService
                  .sendMessage(from, intentResult.response!);
            } else {
              await _services.whatsappService.sendMessage(from,
                  "I'm here to help! Would you like to create a receipt or invoice?");
            }
            break;

          case UserIntent.createReceipt:
            await _services.receiptHandler
                .processReceiptResult(from, text, profile, isInvoice: false);
            break;

          case UserIntent.createInvoice:
            await _services.receiptHandler
                .processReceiptResult(from, text, profile, isInvoice: true);
            break;

          case UserIntent.help:
            await _sendHelpMessage(from);
            break;

          case UserIntent.unknown:
            // Relaxed Fallback: If intent is unknown but text is long, try parsing.
            if (text.length > 20) {
              await _services.receiptHandler
                  .processReceiptResult(from, text, profile, isInvoice: false);
            } else {
              await _services.whatsappService.sendMessage(from,
                  "I didn't quite catch that. You can type 'Menu' to see options or just tell me what you sold!");
            }
            break;
        }
      } catch (e) {
        print('Router Error: $e');
        await _services.whatsappService.sendMessage(from,
            "I'm having a little trouble thinking right now. 😵‍💫 Try telling me what you sold again.");
      }
      break;
  }
}

Future<bool> _handleGlobalCommands(
  String from,
  String lower,
  String originalText,
  BusinessProfile profile,
) async {
  // Greetings / Menu
  if (lower == 'menu' ||
      lower == 'hey' ||
      lower == 'hello' ||
      lower == 'hi' ||
      lower == 'good morning' ||
      lower == 'good afternoon' ||
      lower == 'good evening' ||
      lower == 'yo' ||
      lower == 'start') {
    await _sendWelcomeMessage(from, profile);
    return true;
  }

  // Help Command
  if (lower == 'help' ||
      lower == 'info' ||
      lower == 'how to use' ||
      lower.contains('instructions')) {
    await _sendHelpMessage(from);
    return true;
  }

  if (lower == 'premium' ||
      lower == 'upgrade' ||
      lower == ButtonIds.upgrade ||
      lower == '⭐ upgrade to premium') {
    await _services.subscriptionHandler.showUpgradeMenu(from, profile);
    return true;
  }

  // Handle Subscription Status check
  if (lower == ButtonIds.subStatus || lower == '💎 subscription status') {
    await _services.subscriptionHandler.showSubscriptionStatus(from, profile);
    return true;
  }

  if (lower == 'verify payment' || lower == ButtonIds.verifyPayment) {
    await _services.subscriptionHandler.handleVerifyPayment(from, profile);
    return true;
  }

  if (lower.contains('create receipt') || lower == ButtonIds.createReceipt) {
    await _services.firestoreService
        .updateAction(from, UserAction.createReceipt);
    await _services.whatsappService.sendMessage(
      from,
      'Please provide the receipt details:\n\n- Customer Name\n- Items Bought & Prices\n- Tax (optional)\n- Customer Address (optional)\n- Customer Phone Number (optional)\n\nType *Cancel* to exit.',
    );
    return true;
  }

  if (lower.contains('create invoice') || lower == ButtonIds.createInvoice) {
    await _services.firestoreService
        .updateAction(from, UserAction.createInvoice);
    // Check if bank details exist
    final hasBankDetails =
        profile.bankName != null && profile.accountNumber != null;
    if (hasBankDetails) {
      await _services.whatsappService.sendMessage(
        from,
        'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Tax (optional)\n- Due Date (optional)\n- Client Address (optional)\n- Client Phone Number (optional)\n\nType *Cancel* to exit.',
      );
    } else {
      await _services.whatsappService.sendMessage(
        from,
        'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Tax (optional)\n- Due Date\n\n⚠️ **Also, please include your Bank Details (Bank Name, Account Number, Name) to save for future invoices.**\n\nType *Cancel* to exit.',
      );
    }
    return true;
  }

  if (lower == 'settings' ||
      lower == ButtonIds.settings ||
      lower == '⚙️ settings') {
    if (profile.role != UserRole.admin) {
      await _services.whatsappService
          .sendMessage(from, 'Only Admins can access settings.');
      return true;
    }
    await _services.settingsHandler.showSettingsMenu(from, profile.isPremium);
    return true;
  }

  if (lower == 'edit profile' || lower == ButtonIds.editProfile) {
    if (profile.role != UserRole.admin) {
      await _services.whatsappService
          .sendMessage(from, 'Only Admins can edit the business profile.');
      return true;
    }
    await _services.firestoreService
        .updateAction(from, UserAction.editProfileMenu);
    await _services.settingsHandler.showEditProfileMenu(from);
    return true;
  }

  if (lower == 'manage team' || lower == ButtonIds.manageTeam) {
    if (profile.role != UserRole.admin) {
      await _services.whatsappService
          .sendMessage(from, 'Only Admins can manage team members.');
      return true;
    }
    await _services.settingsHandler.showTeamManagement(from, profile);
    return true;
  }

  if (lower == 'change currency' || lower == ButtonIds.changeCurrency) {
    // Handled in the edit profile section now
    return false;
  }

  if (lower == 'upload logo' || lower == ButtonIds.editLogo) {
    if (profile.role != UserRole.admin) {
      await _services.whatsappService
          .sendMessage(from, 'Only Admins can upload the business logo.');
      return true;
    }
    await _services.firestoreService.updateAction(from, UserAction.editLogo);
    await _services.whatsappService.sendMessage(from,
        'Okay, send me the *New Logo Image*.\n\n⚠️ *If your logo has a transparent background, upload it as a Document so WhatsApp keeps it transparent!*\n\nType *Back* to return or *Cancel* to exit.');
    return true;
  }

  if (lower.startsWith('cancel') ||
      lower == ButtonIds.cancel ||
      lower == 'exit' ||
      lower.startsWith('quit')) {
    await _services.firestoreService.updateAction(from, UserAction.idle);
    await _services.whatsappService.sendMessage(from, 'Action cancelled.');
    return true;
  }

  // Back navigation - returns to parent menu instead of exiting
  if (lower == 'back' || lower == ButtonIds.back) {
    final action = profile.currentAction ?? UserAction.idle;

    // Route to appropriate parent menu based on current action
    switch (action) {
      case UserAction.editName:
      case UserAction.editPhone:
      case UserAction.editAddress:
      case UserAction.editBankDetails:
      case UserAction.editLogo:
      case UserAction.selectTheme:
      case UserAction.selectLayout:
      case UserAction.selectCurrency:
        // Return to Edit Profile menu
        await _services.settingsHandler.showEditProfileMenu(from);
        return true;

      case UserAction.editProfileMenu:
      case UserAction.removeTeamMember:
      case UserAction.confirmRemoveTeamMember:
        // Return to Settings menu
        await _services.settingsHandler
            .showSettingsMenu(from, profile.isPremium);
        return true;

      case UserAction.selectingSubscriptionPlan:
      case UserAction.awaitingEmailForUpgrade:
        // Return to Settings menu
        await _services.settingsHandler
            .showSettingsMenu(from, profile.isPremium);
        return true;

      // ignore: no_default_cases
      default:
        // For other actions, just go idle
        await _services.firestoreService.updateAction(from, UserAction.idle);
        await _services.whatsappService
            .sendMessage(from, 'Returned to main menu.');
        return true;
    }
  }

  return false;
}

Future<void> _sendWelcomeMessage(String to, BusinessProfile profile) async {
  await _services.firestoreService.updateAction(to, UserAction.idle);

  const String bodyText = 'Hey! What can I do for you? 🙋‍♂️\n\n'
      '_Or just send me the details of a sale to quickly generate a receipt!_';

  final List<Map<String, String>> buttons = [
    {'id': ButtonIds.createReceipt, 'title': '🧾 Receipt'},
    {'id': ButtonIds.createInvoice, 'title': '📄 Invoice'},
  ];

  if (profile.role == UserRole.admin) {
    // If they have a pending payment, prioritize the Verify button
    if (profile.pendingPaymentReference != null &&
        profile.pendingPaymentReference!.isNotEmpty) {
      buttons.add({'id': ButtonIds.verifyPayment, 'title': '✅ Verify Payment'});
    } else {
      buttons.add({'id': ButtonIds.settings, 'title': '⚙️ Settings'});
    }
  } else {
    buttons.add({'id': ButtonIds.help, 'title': '❓ Help'});
  }

  await _services.whatsappService.sendInteractiveButtons(to, bodyText, buttons);
}

Future<void> _sendHelpMessage(String to) async {
  await _services.whatsappService.sendMessage(
    to,
    '''
*How to use Remi* 🤖

I'm here to help you create professional Receipts and Invoices in seconds! Here is what I can do:

🧾 *1. Fast Receipts*
Just type the sale details naturally! 
_Example: "Sold 2 pairs of shoes for 15k each and a t-shirt for 5000 to John Doe"_
Or type *Create Receipt* to be guided step-by-step.

📝 *2. Professional Invoices*
Type *Create Invoice* to start. I'll guide you through adding client details, items, tax, and a due date. 
_(Tip: Make sure your Bank Details are saved in your profile first!)_

📸 *3. Magic Image Scanning*
Send me a clear photo of a handwritten receipt or list of items, and I will magically extract the text and digitize it for you! ✨

⚙️ *4. Setup & Branding (Admins)*
Type *Menu* or *Edit Profile* to update your Business Name, Address, and Bank Details. Type *Upload Logo* to add your brand's logo to your documents.

👥 *5. Invite Your Staff (Admins)*
Type *Invite Team Member* to generate a unique 6-character code. Your staff can use this to join your account and generate receipts for your business.

---
💡 *Quick Commands:*
• Type *Menu* to see all options.
• Type *Cancel* at any time to stop a current action.
• Type *Upgrade* to view Premium features! 💎

Need human help? Contact support at woobackbigmlboa@gmail.com
''',
  );
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
