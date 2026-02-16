// ignore: duplicate_ignore
// ignore: lines_longer_than_80_chars
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/firestore_service.dart';
import 'package:receipt_bot/gemini_service.dart';
import 'package:receipt_bot/models.dart';
import 'package:receipt_bot/pdf_service.dart';

// Configuration
// Configuration
final String _verifyToken =
    Platform.environment['VERIFY_TOKEN'] ?? 'my_secure_receipt_token';
final String _whatsappToken = Platform.environment['WHATSAPP_TOKEN'] ?? '';
final String _phoneNumberId = Platform.environment['PHONE_NUMBER_ID'] ?? '';
final String _projectId = Platform.environment['GOOGLE_PROJECT_ID'] ?? '';
final String _geminiApiKey = Platform.environment['GEMINI_API_KEY'] ?? '';

// Service Instances (Lazy initialization or via Middleware)
final _firestoreService = FirestoreService(projectId: _projectId);
late final GeminiService _geminiService;
final _pdfService = PdfService();
bool _servicesInitialized = false;

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

  // Initialize services only for other requests (POST)
  if (!_servicesInitialized) {
    try {
      final serviceAccountContent =
          await File('service_account.json').readAsString();
      await _firestoreService.initialize(serviceAccountContent);
      _geminiService = GeminiService(apiKey: _geminiApiKey);
      _servicesInitialized = true;
    } catch (e) {
      print('Service initialization failed: $e');
      // We continue, but subsequent calls to services might fail
    }
  }

  // 2. Handle Messages (POST)
  if (request.method == HttpMethod.post) {
    print('Received POST request');
    final body = await request.body();
    // print('Raw Body: $body'); // Clean logs
    final json = jsonDecode(body);

    try {
      final entry = json['entry'][0];
      final changes = entry['changes'][0]['value'];

      if (changes['messages'] != null) {
        final message = changes['messages'][0];
        final from = message['from'] as String;
        final type = message['type'] as String;
        var text = '';

        if (type == 'text') {
          text = message['text']['body'] as String;
        } else if (type == 'image') {
          text = (message['caption'] ?? '') as String;
        }

        // Fire and Forget: Process in background to return 200 OK fast
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
    var profile = await _firestoreService.getProfile(from);

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
      // 3. New User Flow (Start)
      if (profile.status == OnboardingStatus.new_user) {
        // Actually, if we just created the profile, we should ask for the name immediately.
        await _sendWhatsAppMessage(from,
            "Welcome to PennyWise! 🤖🧾\n\nI can help you generate professional Receipts & Invoices internally.\n\nTo get started, I'll need a few details:\n1. Business Name\n2. Address\n3. Phone Number\n4. Logo (Optional)\n\nLet's start! What is your *Business Name*?");

        await _firestoreService.updateOnboardingStep(
            from, OnboardingStatus.new_user);
        return;
      }
    }

    // 2. State Machine
    switch (profile.status ?? OnboardingStatus.new_user) {
      case OnboardingStatus.new_user:
        await _firestoreService.updateOnboardingStep(
          from,
          OnboardingStatus.awaiting_address,
          data: {'businessName': text},
        );
        await _sendWhatsAppMessage(
          from,
          'Great! Now, what is your *Business Address*?',
        );
        break;

      case OnboardingStatus.awaiting_address:
        await _firestoreService.updateOnboardingStep(
          from,
          OnboardingStatus.awaiting_phone,
          data: {'businessAddress': text},
        );
        await _sendWhatsAppMessage(
          from,
          'Got it. What is your *Business Phone Number*',
        );
        break;

      case OnboardingStatus.awaiting_phone:
        await _firestoreService.updateOnboardingStep(
          from,
          OnboardingStatus.awaiting_logo,
          data: {'displayPhoneNumber': text},
        );
        await _sendWhatsAppMessage(
          from,
          "Almost done! Please upload a transparent **PNG of your Business Logo**.\n\nType *Skip* if you don't have one.",
        );
        break;

      case OnboardingStatus.awaiting_logo:
        if (type == 'image') {
          // Handle Image Upload
          final imageId = messageData['image']['id'];
          // 1. Get WhatsApp URL
          final tempUrl = await _getWhatsAppMediaUrl(imageId as String);

          // 2. Download Bytes
          final bytes = await _downloadFileBytes(tempUrl);

          // 3. Upload to Cloud Storage
          final publicUrl = await _firestoreService.uploadFile(
            'logos/$from.jpg',
            bytes,
            'image/jpeg',
          );

          await _firestoreService.saveLogoUrl(from, publicUrl);

          await _sendWhatsAppMessage(
            from,
            "Setup Complete! 🎉\n\nYou can now create receipts!\n\nSend 'Create Receipt' to start, or just type the details.",
          );
        } else if (text.toLowerCase() == 'skip') {
          // SKIP LOGO
          await _firestoreService.updateOnboardingStep(
            from,
            OnboardingStatus.active,
            data: {'logoUrl': null}, // Ensure it's null
          );
          await _sendWhatsAppMessage(
            from,
            "Setup Complete! 🎉\n\nYou can now create receipts!\n\nSend 'Create Receipt' to start, or just type the details.",
          );
        } else {
          await _sendWhatsAppMessage(
            from,
            'Please send an **image** for your logo, or type *Skip* to proceed without one.',
          );
        }
        break;

      case OnboardingStatus.active:
        await _handleActiveUser(from, text, type, messageData, profile);
        break;
    }
  } catch (e) {
    print('Error in _handleMessage: $e');
    // If we fail outside the state machine (e.g. Firestore error)
    await _sendWhatsAppMessage(from, 'System Error: $e');
  }
}

Future<void> _handleActiveUser(
  String from,
  String text,
  String type,
  Map<String, dynamic> messageData,
  BusinessProfile profile,
) async {
  // 1. IMAGE SCANNING LOGIC (NEW!)
  if (type == 'image') {
    await _sendWhatsAppMessage(from, "Scanning image... 🤖");

    try {
      // A. Get the image from WhatsApp
      final imageId = messageData['image']['id'] as String;
      final url = await _getWhatsAppMediaUrl(imageId);
      // Note: _downloadFileBytes returns List<int>, need to convert to Uint8List
      final imageBytesList = await _downloadFileBytes(url);
      final imageBytes = Uint8List.fromList(imageBytesList);

      // B. Send to Gemini Vision
      final transaction = await _geminiService.parseImageTransaction(
        imageBytes,
        currencySymbol: profile.currencySymbol,
        currencyCode: profile.currencyCode,
      );

      // C. Save & Ask for Theme (Same as text flow)
      await _firestoreService.updateProfileData(from, {
        'pendingTransaction': jsonEncode(transaction.toJson()),
        'currentAction': UserAction.selectTheme.name
      });

      await _sendWhatsAppMessage(from,
          "I found ${transaction.items.length} items totaling ${profile.currencySymbol}${transaction.totalAmount}!\n\nSelect a style:\n1️⃣ *Classic*\n2️⃣ *Beige*\n3️⃣ *Blue*");
    } catch (e) {
      print("Image Scan Error: $e");
      await _sendWhatsAppMessage(from,
          "⚠️ I couldn't read that image clearly. Please try sending a clearer photo or type the details.");
    }
    return;
  }

  // 2. TEXT COMMANDS (Global)
  if (type == 'text') {
    final lower = text.toLowerCase().trim();

    // Global Command Handler
    final isHandled = await _handleGlobalCommands(from, lower, text, profile);
    if (isHandled) return;
  }

  // 3. Handle Current Action
  switch (profile.currentAction ?? UserAction.idle) {
    case UserAction.createReceipt:
      await _processReceiptResult(from, text, profile, isInvoice: false);
      break;
    case UserAction.createInvoice:
      await _processReceiptResult(from, text, profile, isInvoice: true);
      break;
    case UserAction.editProfileMenu:
      if (text.contains('1')) {
        await _firestoreService.updateAction(from, UserAction.editName);
        await _sendWhatsAppMessage(
          from,
          'Okay, send me the **New Business Name**.',
        );
      } else if (text.contains('2')) {
        await _firestoreService.updateAction(from, UserAction.editPhone);
        await _sendWhatsAppMessage(
          from,
          'Okay, send me the **New Phone Number**.',
        );
      } else if (text.contains('3')) {
        await _firestoreService.updateAction(from, UserAction.editBankDetails);
        await _sendWhatsAppMessage(
          from,
          'Okay, send me your **Bank Details**:\n\nBank Name, Account Number, Account Name',
        );
      } else if (text.contains('4')) {
        await _firestoreService.updateAction(from, UserAction.selectTheme);
        await _sendWhatsAppMessage(
          from,
          'Select a default style for your documents:\n\n1️⃣ Classic (B&W)\n2️⃣ Beige Corporate\n3️⃣ Blue Accent\n\nReply with 1, 2, or 3.',
        );
      } else if (text.contains('5')) {
        await _firestoreService.updateAction(from, UserAction.editAddress);
        await _sendWhatsAppMessage(
          from,
          'Okay, send me the **New Business Address**.',
        );
      } else {
        await _sendWhatsAppMessage(from, 'Please reply with 1, 2, 3, 4, or 5.');
      }
      break;

    case UserAction.selectCurrency:
      final index = int.tryParse(text) ?? 0;
      const currencies = CountryUtils.supportedCurrencies;

      if (index > 0 && index <= currencies.length) {
        final selected = currencies[index - 1];
        await _firestoreService.updateProfileData(from, {
          'currencyCode': selected['code'],
          'currencySymbol': selected['symbol'],
        });

        // Update local profile instance for immediate use if needed (though we return idle next)
        profile = profile.copyWith(
          currencyCode: selected['code'],
          currencySymbol: selected['symbol'],
        );

        await _firestoreService.updateAction(from, UserAction.idle);
        await _sendWhatsAppMessage(from,
            'Currency updated to ${selected['code']} (${selected['symbol']})! ✅');
      } else {
        await _sendWhatsAppMessage(
            from, 'Please reply with a valid number from the list.');
      }
      break;

    case UserAction.editBankDetails:
      // Use Gemini to parse bank details
      try {
        final transaction = await _geminiService.parseTransaction(text);
        if (transaction.bankName != null) {
          await _firestoreService.updateOnboardingStep(
            from,
            OnboardingStatus.active,
            data: {
              'bankName': transaction.bankName,
              'accountNumber': transaction.accountNumber,
              'accountName': transaction.accountName,
            },
          );
          await _sendWhatsAppMessage(from, 'Bank Details Updated! ✅');
        } else {
          await _sendWhatsAppMessage(
            from,
            "I couldn't find bank details. Please try again (e.g. GTBank, 0123456789, Name).",
          );
        }
        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppMessage(
          from,
          'What else would you like to update?\n\n1️⃣ Business Name\n2️⃣ Phone Number\n3️⃣ Bank Details\n4️⃣ Theme / Style\n5️⃣ Address\n\nType *Menu* to finish.',
        );
      } catch (e) {
        await _sendWhatsAppMessage(
          from,
          'Error parsing details. Please try again.',
        );
      }
      break;

    case UserAction.selectTheme:
      await _handleThemeSelection(from, text, profile);
      break;

    case UserAction.editName:
      if (type == 'text') {
        await _firestoreService.updateOnboardingStep(
          from,
          OnboardingStatus.active,
          data: {'businessName': text},
        );
        await _sendWhatsAppMessage(from, "Business Name updated to '$text'! ✅");

        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppMessage(
          from,
          'What else would you like to update?\n\n1️⃣ Business Name\n2️⃣ Phone Number\n3️⃣ Bank Details\n4️⃣ Theme / Style\n5️⃣ Address\n\nType *Menu* to finish.',
        );
      } else {
        await _sendWhatsAppMessage(from, 'Please send text for the name.');
      }
      break;

    case UserAction.editPhone:
      if (type == 'text') {
        await _firestoreService.updateOnboardingStep(
          from,
          OnboardingStatus.active,
          data: {'displayPhoneNumber': text},
        );
        await _sendWhatsAppMessage(from, "Phone Number updated to '$text'! ✅");
        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppMessage(
          from,
          'What else would you like to update?\n\n1️⃣ Business Name\n2️⃣ Phone Number\n3️⃣ Bank Details\n4️⃣ Theme / Style\n5️⃣ Address\n\nType *Menu* to finish.',
        );
      } else {
        await _sendWhatsAppMessage(
          from,
          'Please send text for the phone number.',
        );
      }
      break;

    case UserAction.editAddress:
      if (type == 'text') {
        await _firestoreService.updateOnboardingStep(
          from,
          OnboardingStatus.active,
          data: {'businessAddress': text},
        );
        await _sendWhatsAppMessage(from, "Address updated to '$text'! ✅");
        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppMessage(
          from,
          'What else would you like to update?\n\n1️⃣ Business Name\n2️⃣ Phone Number\n3️⃣ Bank Details\n4️⃣ Theme / Style\n5️⃣ Address\n\nType *Menu* to finish.',
        );
      } else {
        await _sendWhatsAppMessage(
          from,
          'Please send text for the address.',
        );
      }
      break;

    case UserAction.editLogo:
      if (type == 'image') {
        final imageId = messageData['image']['id'];
        final tempUrl = await _getWhatsAppMediaUrl(imageId as String);

        final bytes = await _downloadFileBytes(tempUrl);
        final publicUrl = await _firestoreService.uploadFile(
          'logos/$from.jpg',
          bytes,
          'image/jpeg',
        );

        await _firestoreService.saveLogoUrl(from, publicUrl);
        await _sendWhatsAppMessage(from, 'Logo updated successfully! 🖼️');

        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppMessage(
          from,
          'What else would you like to update?\n\n1️⃣ Business Name\n2️⃣ Phone Number\n3️⃣ Bank Details\n4️⃣ Theme / Style\n5️⃣ Address\n\nType *Menu* to finish.',
        );
      } else {
        await _sendWhatsAppMessage(from, 'Please send an image.');
      }
      break;

    case UserAction.idle:
      // Legacy Flow / Fallback
      if (type == 'text') {
        // Only attempt to parse if it contains numbers or keywords, or is of sufficient length.
        // If it's short and not a command, ask for clarification.
        final lower = text.toLowerCase();
        // Check for common receipt content indicators (relaxed)
        // If it contains numbers OR newlines (list format) OR is long enough
        bool looksLikeReceipt = text.length > 15 ||
            text.contains(RegExp(r'\d')) ||
            text.contains('\n') ||
            lower.contains('bought') ||
            lower.contains('items');

        if (looksLikeReceipt) {
          await _processReceiptResult(from, text, profile, isInvoice: false);
        } else {
          await _sendWhatsAppMessage(
            from,
            "I'm not sure if that's a receipt. Please send details like 'Items, Prices' or type 'Create Receipt' to start.",
          );
        }
      } else {
        await _sendWhatsAppMessage(
          from,
          "Please send text to generate a receipt or type 'Menu'.",
        );
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
    await _firestoreService.updateAction(from, UserAction.idle);
    await _sendWhatsAppMessage(
      from,
      'Hey! What can I do for you?\n\n🔹 *Create Receipt*\n🔹 *Create Invoice*\n🔹 *Edit Profile* (Name, Address, Bank, Theme)\n🔹 *Change Currency* (${profile.currencyCode})\n🔹 *Upload New Logo*\n🔹 *Cancel* to exit',
    );
    return true;
  }

  // Help Command
  if (lower == 'help' ||
      lower == 'info' ||
      lower == 'how to use' ||
      lower.contains('instructions')) {
    await _sendWhatsAppMessage(
      from,
      '''
*How to use PennyWise* 🤖🧾

I can help you create professional Receipts and Invoices quickly!

*1. Create a Receipt*
Simply type the details of the sale.
Example: *"Sold 2 pairs of shoes for 15k each and a t-shirt for 5000 to John Doe"*
OR type *"Create Receipt"* to follow the steps.

*2. Create an Invoice*
Type *"Create Invoice"* to start. I'll ask for client details, items, and due date.
(Make sure your Bank Details are set in your profile!)

*3. Edit Profile*
Type *"Edit Profile"* or *"Menu"* to update your Business Name, Address, Phone, Logo, or Bank Details.

*4. Change Currency*
Type *"Change Currency"* to switch between NGN, USD, GBP, etc.

*5. Image Parsing*
Send me a photo of a handwritten receipt or note, and I'll try to digitize it for you!

Need more help? Contact support at woobackbigmlboa@gmail.com.
''',
    );
    return true;
  }

  if (lower.contains('create receipt')) {
    await _firestoreService.updateAction(from, UserAction.createReceipt);
    await _sendWhatsAppMessage(
      from,
      'Please provide the receipt details:\n\n- Customer Name\n- Items Bought & Prices\n- Address (optional)\n- Phone (optional)',
    );
    return true;
  }

  if (lower.contains('create invoice')) {
    await _firestoreService.updateAction(from, UserAction.createInvoice);
    // Check if bank details exist
    final hasBankDetails =
        profile.bankName != null && profile.accountNumber != null;
    if (hasBankDetails) {
      await _sendWhatsAppMessage(
        from,
        'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Due Date (optional)\n- Address/Phone',
      );
    } else {
      await _sendWhatsAppMessage(
        from,
        'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Due Date\n\n⚠️ **Also, please include your Bank Details (Bank Name, Account Number, Name) to save for future invoices.**',
      );
    }
    return true;
  }

  if (lower == 'edit profile') {
    await _firestoreService.updateAction(from, UserAction.editProfileMenu);
    await _sendWhatsAppMessage(
      from,
      'What would you like to update?\n\n1️⃣ Business Name\n2️⃣ Phone Number\n3️⃣ Bank Details\n4️⃣ Theme / Style\n\nReply with the number.',
    );
    return true;
  }

  if (lower == 'change currency') {
    await _firestoreService.updateAction(from, UserAction.selectCurrency);

    const currencies = CountryUtils.supportedCurrencies;
    String message = 'Select your currency:\n\n';
    for (int i = 0; i < currencies.length; i++) {
      message +=
          '${i + 1}️⃣ ${currencies[i]['code']} (${currencies[i]['symbol']}) - ${currencies[i]['name']}\n';
    }
    message += '\nReply with the number.';

    await _sendWhatsAppMessage(from, message);
    return true;
  }

  if (lower == 'upload new logo') {
    await _firestoreService.updateAction(from, UserAction.editLogo);
    await _sendWhatsAppMessage(from, 'Okay, send me the **New Logo Image**.');
    return true;
  }

  if (lower == 'cancel') {
    await _firestoreService.updateAction(from, UserAction.idle);
    await _sendWhatsAppMessage(from, 'Action cancelled.');
    return true;
  }

  return false;
}

Future<void> _processReceiptResult(
  String from,
  String text,
  BusinessProfile profile, {
  required bool isInvoice,
}) async {
  await _sendWhatsAppMessage(
    from,
    'Generating ${isInvoice ? "Invoice" : "Receipt"}... ⏳',
  );
  try {
    // AI Parsing
    final transaction = await _geminiService.parseTransaction(
      text,
      currencySymbol: profile.currencySymbol,
      currencyCode: profile.currencyCode,
    );

    // Validate Transaction
    if (transaction.items.isEmpty && transaction.totalAmount == 0) {
      await _sendWhatsAppMessage(
        from,
        "I couldn't find any items or prices in that message. Please try again with details like: 'Customer Name, Items, Prices'.",
      );
      // Keep them in the same action state to try again
      return;
    }

    // 4. Update Profile with new bank details if found
    if (transaction.bankName != null || transaction.accountNumber != null) {
      final updates = <String, dynamic>{};
      if (transaction.bankName != null) {
        updates['bankName'] = transaction.bankName;
      }
      if (transaction.accountNumber != null) {
        updates['accountNumber'] = transaction.accountNumber;
      }
      if (transaction.accountName != null) {
        updates['accountName'] = transaction.accountName;
      }

      if (updates.isNotEmpty) {
        await _firestoreService.updateProfileData(from, updates);
        // Update local profile for PDF generation
        profile = profile.copyWith(
          bankName: transaction.bankName ?? profile.bankName,
          accountNumber: transaction.accountNumber ?? profile.accountNumber,
          accountName: transaction.accountName ?? profile.accountName,
        );
      }
    }

    // Phase B check: If we have a theme preference, use it.
    if (profile.themeIndex != null) {
      // Direct Generation
      transaction.type.index; // Just to access it
      // Note: We might want to mutate the transaction type if isInvoice is true
      // But transaction already has type from Gemini.
      // Let's rely on Gemini or force it if needed.
      // But for now, let's just generate.

      await _generateAndSendPDF(
        from,
        profile,
        transaction,
        profile.themeIndex!,
      );
      return;
    }

    // 5. Save Pending Transaction & Ask for Theme
    await _firestoreService.updateProfileData(from, {
      'pendingTransaction': jsonEncode(transaction.toJson()),
      'currentAction': UserAction.selectTheme.name,
    });

    await _sendWhatsAppMessage(
        from,
        "Got it! 🧾\n\nSelect a style for your ${isInvoice ? 'Invoice' : 'Receipt'}:\n\n"
        '1️⃣ *Classic (B&W)*\n'
        '2️⃣ *Beige Corporate*\n'
        '3️⃣ *Blue Accent*\n\n'
        'Reply with 1, 2, or 3.');
  } catch (e) {
    print('Error generating receipt: $e');
    await _sendWhatsAppMessage(
      from,
      "⚠️ Error: I couldn't process that.\n\nDetails: $e\n\nPlease try again or type 'Create Receipt' for help.",
    );
  }
}

Future<void> _handleThemeSelection(
  String from,
  String body,
  BusinessProfile profile,
) async {
  int? themeIndex;

  final lower = body.toLowerCase();
  if (lower.contains('1') || lower.contains('classic')) {
    themeIndex = 0;
  } else if (lower.contains('2') || lower.contains('beige')) {
    themeIndex = 1;
  } else if (lower.contains('3') || lower.contains('blue')) {
    themeIndex = 2;
  }

  if (themeIndex == null) {
    await _sendWhatsAppMessage(
      from,
      'Please reply with 1, 2, or 3 to select a style.',
    );
    return;
  }

  // Update Profile with new theme preference
  await _firestoreService.updateProfileData(from, {'themeIndex': themeIndex});
  profile = profile.copyWith(themeIndex: themeIndex);

  // If no pending transaction, this was just a profile update
  if (profile.pendingTransaction == null) {
    await _sendWhatsAppMessage(from, 'Default theme updated! ✅');
    // Go back to profile menu
    await _firestoreService.updateAction(from, UserAction.editProfileMenu);
    await _sendWhatsAppMessage(
      from,
      'What else would you like to update?\n\n1️⃣ Business Name\n2️⃣ Phone Number\n3️⃣ Bank Details\n4️⃣ Theme / Style\n5️⃣ Address\n\nType *Menu* to finish.',
    );
    return;
  }

  // Otherwise, continue to generate the pending receipt
  await _generateAndSendPDF(
      from, profile, profile.pendingTransaction!, themeIndex);
}

Future<void> _generateAndSendPDF(
  String from,
  BusinessProfile profile,
  Transaction transaction,
  int themeIndex,
) async {
  await _sendWhatsAppMessage(from, 'Generating PDF... ⏳');

  try {
    final pdfBytes = await _pdfService.generateReceipt(
      profile,
      transaction,
      themeIndex: themeIndex,
    );

    // Upload and Send
    final fileName =
        '${transaction.type == TransactionType.invoice ? "invoice" : "receipt"}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final pdfUrl = await _firestoreService.uploadFile(
      'receipts/$from/$fileName',
      pdfBytes,
      'application/pdf',
    );

    await _sendWhatsAppMessage(
      from,
      "Here is your ${transaction.type == TransactionType.invoice ? "Invoice" : "Receipt"}! 👇",
    );
    await _sendWhatsAppMedia(from, pdfUrl, fileName);

    await _firestoreService
        .updateProfileData(from, {'pendingTransaction': ''}); // Clear pending
    await _firestoreService.updateAction(from, UserAction.idle);
  } catch (e) {
    print('Error generating PDF: $e');
    await _sendWhatsAppMessage(
      from,
      'Failed to generate PDF. Please try again.',
    );
    await _firestoreService.updateAction(from, UserAction.idle);
  }
}

Future<void> _sendWhatsAppMessage(String to, String message) async {
  final url =
      Uri.parse('https://graph.facebook.com/v17.0/$_phoneNumberId/messages');
  final headers = {
    'Authorization': 'Bearer $_whatsappToken',
    'Content-Type': 'application/json',
  };
  final body = jsonEncode({
    'messaging_product': 'whatsapp',
    'to': to,
    'type': 'text',
    'text': {'body': message},
  });

  try {
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode != 200) {
      print('Failed to send WhatsApp message: ${response.body}');
    }
  } catch (e) {
    print('Error sending WhatsApp message: $e');
  }
}

Future<String> _getWhatsAppMediaUrl(String mediaId) async {
  // 1. Get URL from Media ID
  final url = Uri.parse('https://graph.facebook.com/v17.0/$mediaId');
  final headers = {
    'Authorization': 'Bearer $_whatsappToken',
  };
  final response = await http.get(url, headers: headers);
  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);
    return json['url'] as String; // This is the download URL
  } else {
    throw Exception('Failed to get media URL: ${response.body}');
  }
}

Future<List<int>> _downloadFileBytes(String url) async {
  final headers = {
    'Authorization': 'Bearer $_whatsappToken', // Required for WhatsApp media
  };

  final response = await http.get(Uri.parse(url), headers: headers);
  if (response.statusCode == 200) {
    return response.bodyBytes;
  } else {
    throw Exception('Failed to download file: ${response.statusCode}');
  }
}

Future<void> _sendWhatsAppMedia(
  String to,
  String mediaUrl,
  String filename,
) async {
  final url =
      Uri.parse('https://graph.facebook.com/v17.0/$_phoneNumberId/messages');
  final headers = {
    'Authorization': 'Bearer $_whatsappToken',
    'Content-Type': 'application/json',
  };

  final body = jsonEncode({
    'messaging_product': 'whatsapp',
    'to': to,
    'type': 'document',
    'document': {
      'link': mediaUrl,
      'filename': filename,
      // 'caption': 'Here is your document'
    },
  });

  try {
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode != 200) {
      print('Failed to send WhatsApp media: ${response.body}');
    }
  } catch (e) {
    print('Error sending WhatsApp media: $e');
  }
}
