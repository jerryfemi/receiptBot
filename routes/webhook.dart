// ignore: duplicate_ignore
// ignore: lines_longer_than_80_chars
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/gemini_service.dart';
import 'package:receipt_bot/services/pdf_service.dart';

// Configuration
final String _verifyToken = Platform.environment['VERIFY_TOKEN'] ?? '';
final String _whatsappToken = Platform.environment['WHATSAPP_TOKEN'] ?? '';
final String _phoneNumberId = Platform.environment['PHONE_NUMBER_ID'] ?? '';
final String _projectId =
    Platform.environment['GOOGLE_PROJECT_ID'] ?? 'invoicemaker-b3876';
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
      await _firestoreService.initialize();
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
        await _sendWhatsAppMessage(from,
            "Welcome! \n\nI can help you generate professional Receipts & Invoices internally.\n\nAre you here to:\n1️⃣ Create your own Business Profile\n2️⃣ Join a Team via Invite Code\n\nReply with 1 or 2.");

        await _firestoreService.updateOnboardingStep(
            from, OnboardingStatus.awaiting_setup_choice);
        return;
      }
    }

    // 2. State Machine
    switch (profile.status ?? OnboardingStatus.new_user) {
      case OnboardingStatus.new_user:
        await _sendWhatsAppInteractiveButtons(
          from,
          "Welcome! \n\nI can help you generate professional Receipts & Invoices internally.\n\nAre you here to:",
          [
            {'id': '1', 'title': '🏢 Create Profile'},
            {'id': '2', 'title': '🤝 Join Team'},
          ],
        );
        await _firestoreService.updateOnboardingStep(
            from, OnboardingStatus.awaiting_setup_choice);
        break;

      case OnboardingStatus.awaiting_setup_choice:
        if (text.trim() == '1') {
          await _firestoreService.updateOnboardingStep(
            from,
            OnboardingStatus
                .awaiting_address, // Next step is business name, but we store in 'businessName' during this step
          );
          await _sendWhatsAppMessage(
              from, "Let's start! What is your *Business Name*?");
        } else if (text.trim() == '2') {
          await _firestoreService.updateOnboardingStep(
            from,
            OnboardingStatus.awaiting_invite_code,
          );
          await _sendWhatsAppMessage(from,
              "Great! Please reply with the 6-character Invite Code your admin gave you.\n\nType *Cancel* to exit.");
        } else {
          await _sendWhatsAppInteractiveButtons(
            from,
            "Please make a selection to proceed:",
            [
              {'id': '1', 'title': '🏢 Create Profile'},
              {'id': '2', 'title': '🤝 Join Team'},
            ],
          );
        }
        break;

      case OnboardingStatus.awaiting_invite_code:
        final code = text.trim().toUpperCase();
        await _sendWhatsAppMessage(from, "Checking code... 🔎");

        final orgId =
            await _firestoreService.findOrganizationByInviteCode(code);
        if (orgId != null) {
          final org = await _firestoreService.getOrganization(orgId);
          await _firestoreService.updateProfileData(from, {
            'orgId': orgId,
            'role': UserRole.agent.name,
            'status': OnboardingStatus.active.name,
          });
          await _sendWhatsAppMessage(from,
              "Success! 🎉 You are now linked to **${org?.businessName ?? 'your team'}** as a Sales Agent.\n\nYou can now send me receipt details and I will generate them using the company's official template.");
        } else {
          await _sendWhatsAppMessage(from,
              "Oops, that code is invalid. Please try again or ask your admin for the correct code, or type 'cancel' to restart.");
        }
        break;

      case OnboardingStatus.awaiting_address:
        // Here `text` is the businessName provided
        final newOrgId = await _firestoreService.createOrganization(text);
        await _firestoreService.updateProfileData(from, {
          'orgId': newOrgId,
          'role': UserRole.admin.name,
        });

        await _firestoreService.updateOnboardingStep(
          from,
          OnboardingStatus.awaiting_phone,
          data: {'businessName': text},
        );
        await _sendWhatsAppMessage(
          from,
          'Great! Now, what is your *Business Address*?\n\nType *Cancel* to exit.',
        );
        break;

      case OnboardingStatus.awaiting_phone:
        await _firestoreService.updateOnboardingStep(
          from,
          OnboardingStatus.awaiting_logo,
          data: {'businessAddress': text},
        );
        if (profile.orgId != null) {
          await _firestoreService.updateOrganizationData(
            profile.orgId!,
            {'businessAddress': text},
          );
        }
        await _sendWhatsAppMessage(
          from,
          "Almost done! Please upload a transparent **PNG of your Business Logo**.\n\nType *Skip* if you don't have one, or *Cancel* to exit.",
        );
        break;

      case OnboardingStatus.awaiting_logo:
        if (type == 'image' || type == 'document') {
          // Handle Image or Document Upload
          final mediaId = type == 'image'
              ? messageData['image']['id']
              : messageData['document']['id'];
          // 1. Get WhatsApp URL
          final tempUrl = await _getWhatsAppMediaUrl(mediaId as String);

          // 2. Download Bytes
          final bytes = await _downloadFileBytes(tempUrl);

          // 3. Upload to Cloud Storage
          final publicUrl = await _firestoreService.uploadFile(
            'logos/$from.jpg',
            bytes,
            'image/jpeg',
          );

          await _firestoreService.saveLogoUrl(from, publicUrl);
          if (profile.orgId != null) {
            await _firestoreService.updateOrganizationData(
              profile.orgId!,
              {'logoUrl': publicUrl},
            );
          }

          await _sendWhatsAppMessage(
            from,
            "Setup Complete! 🎉\n\nYou can now create receipts and invoices.\n\n🔹 Type *Create Receipt* to make a receipt\n🔹 Type *Create Invoice* to make an invoice\n🔹 Type *Menu* to see quick actions\n🔹 Type *Help* for more info",
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
            "Setup Complete! 🎉\n\nYou can now create receipts and invoices.\n\n🔹 Type *Create Receipt* to make a receipt\n🔹 Type *Create Invoice* to make an invoice\n🔹 Type *Menu* to see quick actions\n🔹 Type *Help* for more info",
          );
        } else {
          await _sendWhatsAppMessage(
            from,
            'Please send an **image or document** for your logo, or type *Skip* to proceed without one.',
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
  // 1. IMAGE HANDLING
  if (type == 'image') {
    // A. Priority: Check if we are in a specific flow that needs an image (e.g. Logo Upload)
    if (profile.currentAction == UserAction.editLogo ||
        profile.status == OnboardingStatus.awaiting_logo) {
      // Let the switch statement handle it below
    }
    // B. Otherwise: Default to Image Scanning (Receipt Parsing)
    else {
      await _sendWhatsAppMessage(from, "Scanning image... 🔎");

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

        await _sendWhatsAppInteractiveButtons(
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
        await _sendWhatsAppMessage(from,
            "⚠️ I couldn't read that image clearly. Please try sending a clearer photo or type the details.");
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
      await _processReceiptResult(from, text, profile, isInvoice: false);
      break;
    case UserAction.createInvoice:
      await _processReceiptResult(from, text, profile, isInvoice: true);
      break;
    case UserAction.selectLayout:
      await _handleLayoutSelection(from, text, profile);
      break;
    case UserAction.editProfileMenu:
      if (profile.role != UserRole.admin) {
        await _sendWhatsAppMessage(from, "Only Admins can edit the profile.");
        await _firestoreService.updateAction(from, UserAction.idle);
        return;
      }
      final lowerText = text.toLowerCase().trim();
      if (lowerText == '1' ||
          lowerText == 'btn_edit_name' ||
          lowerText == 'business name') {
        await _firestoreService.updateAction(from, UserAction.editName);
        await _sendWhatsAppMessage(
          from,
          'Okay, send me the **New Business Name**.\n\nType *Cancel* to exit.',
        );
      } else if (lowerText == '2' ||
          lowerText == 'btn_edit_phone' ||
          lowerText == 'phone number') {
        await _firestoreService.updateAction(from, UserAction.editPhone);
        await _sendWhatsAppMessage(
          from,
          'Okay, send me the **New Phone Number**.\n\nType *Cancel* to exit.',
        );
      } else if (lowerText == '3' ||
          lowerText == 'btn_edit_bank' ||
          lowerText == 'bank details') {
        await _firestoreService.updateAction(from, UserAction.editBankDetails);
        await _sendWhatsAppMessage(
          from,
          'Okay, send me your **Bank Details**:\n\nBank Name, Account Number, Account Name\n\nType *Cancel* to exit.',
        );
      } else if (lowerText == '4' ||
          lowerText == 'btn_edit_theme' ||
          lowerText == 'theme') {
        await _firestoreService.updateAction(from, UserAction.selectTheme);
        await _sendWhatsAppInteractiveButtons(
          from,
          "Select a new **Theme (Color)**:",
          [
            {'id': 'theme_classic', 'title': 'B&W (Classic)'},
            {'id': 'theme_beige', 'title': 'Beige'},
          ],
        );
      } else if (lowerText == '5' ||
          lowerText == 'btn_edit_layout' ||
          lowerText == 'layout') {
        await _firestoreService.updateAction(from, UserAction.selectLayout);
        await _sendWhatsAppMessage(
          from,
          "Please select a **Layout Structure**.",
        );
        // Send Layout 1
        await _sendWhatsAppMedia(from,
            'https://dummyimage.com/600x800/fff/000.png&text=Classic', 'image',
            caption: '1️⃣ Classic (Original standard layout)');
        // Send Layout 2
        await _sendWhatsAppMedia(from,
            'https://dummyimage.com/600x800/fff/000.png&text=Modern', 'image',
            caption: '2️⃣ Modern (Elegant script font)');
        // Send Layout 3
        await _sendWhatsAppMedia(from,
            'https://dummyimage.com/600x800/fff/000.png&text=Minimal', 'image',
            caption: '3️⃣ Minimal (Strict grid structure)');
        // Send Layout 4
        await _sendWhatsAppMedia(from,
            'https://dummyimage.com/600x800/fff/000.png&text=Standard', 'image',
            caption:
                '4️⃣ Standard (Premium structured match)\n\nReply with 1, 2, 3, or 4.');
      } else if (lowerText == '6' ||
          lowerText == 'btn_edit_address' ||
          lowerText == 'address') {
        await _firestoreService.updateAction(from, UserAction.editAddress);
        await _sendWhatsAppMessage(
          from,
          'Okay, send me the **New Business Address**.\n\nType *Cancel* to exit.',
        );
      } else {
        await _sendWhatsAppMessage(from,
            'Please select an option from the list or reply with a number (1-6).');
      }
      break;

    case UserAction.selectCurrency:
      final index = int.tryParse(text) ?? 0;
      const currencies = CountryUtils.supportedCurrencies;

      if (index > 0 && index <= currencies.length) {
        final selected = currencies[index - 1];
        try {
          await _updateProfileAndOrg(from, profile, {
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
        } catch (e) {
          print('Error updating currency: $e');
          await _sendWhatsAppMessage(
              from, 'Failed to update currency. Please try again later.');
          await _firestoreService.updateAction(from, UserAction.idle);
        }
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
          await _updateProfileAndOrg(from, profile, {
            'bankName': transaction.bankName,
            'accountNumber': transaction.accountNumber,
            'accountName': transaction.accountName,
          });
          await _sendWhatsAppMessage(from, 'Bank Details Updated! ✅');
        } else {
          await _sendWhatsAppMessage(
            from,
            "I couldn't find bank details. Please try again (e.g. GTBank, 0123456789, Name).",
          );
        }
        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppInteractiveList(
          from,
          'What else would you like to update? 👇',
          'View Options',
          'Edit Profile',
          [
            {'id': 'btn_edit_name', 'title': 'Business Name'},
            {'id': 'btn_edit_phone', 'title': 'Phone Number'},
            {'id': 'btn_edit_bank', 'title': 'Bank Details'},
            {'id': 'btn_edit_theme', 'title': 'Theme'},
            {'id': 'btn_edit_layout', 'title': 'Layout'},
            {'id': 'btn_edit_address', 'title': 'Business Address'},
          ],
        );
      } catch (e) {
        await _sendWhatsAppMessage(
          from,
          'Error parsing details. Please try again.',
        );
      }
      break;

    case UserAction.awaitingInvoiceBankDetails:
      try {
        final transactionInfo = await _geminiService.parseTransaction(text);
        if (transactionInfo.bankName != null) {
          await _updateProfileAndOrg(from, profile, {
            'bankName': transactionInfo.bankName,
            'accountNumber': transactionInfo.accountNumber,
            'accountName': transactionInfo.accountName,
          });

          profile = profile.copyWith(
            bankName: transactionInfo.bankName,
            accountNumber: transactionInfo.accountNumber,
            accountName: transactionInfo.accountName,
          );

          await _sendWhatsAppMessage(from, 'Bank Details Saved! ✅');

          if (profile.pendingTransaction != null) {
            final pendingTx = profile.pendingTransaction!;

            if (profile.themeIndex != null) {
              await _generateAndSendPDF(
                from,
                profile,
                pendingTx,
                profile.themeIndex!,
              );
            } else {
              await _sendWhatsAppInteractiveButtons(
                from,
                "Got it! 🧾\n\nSelect a style for your Invoice:",
                [
                  {'id': 'theme_classic', 'title': 'B&W (Classic)'},
                  {'id': 'theme_beige', 'title': 'Beige'},
                ],
              );
              await _firestoreService.updateAction(
                  from, UserAction.selectTheme);
            }
          } else {
            // Unlikely fallback
            await _firestoreService.updateAction(from, UserAction.idle);
          }
        } else {
          await _sendWhatsAppMessage(
            from,
            "I couldn't find bank details. Please try again (e.g. Bank, 0123456789, Name). Type *Cancel* to exit.",
          );
        }
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
        try {
          await _updateProfileAndOrg(from, profile, {'businessName': text});
          await _sendWhatsAppMessage(
              from, "Business Name updated to '$text'! ✅");
        } catch (e) {
          print('Error updating business name: $e');
          await _sendWhatsAppMessage(
              from, 'Failed to update business name. Please try again.');
        }

        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppInteractiveList(
          from,
          'What else would you like to update? 👇',
          'View Options',
          'Edit Profile',
          [
            {'id': 'btn_edit_name', 'title': 'Business Name'},
            {'id': 'btn_edit_phone', 'title': 'Phone Number'},
            {'id': 'btn_edit_bank', 'title': 'Bank Details'},
            {'id': 'btn_edit_theme', 'title': 'Theme'},
            {'id': 'btn_edit_layout', 'title': 'Layout'},
            {'id': 'btn_edit_address', 'title': 'Business Address'},
          ],
        );
      } else {
        await _sendWhatsAppMessage(from, 'Please send text for the name.');
      }
      break;

    case UserAction.editPhone:
      if (type == 'text') {
        try {
          await _updateProfileAndOrg(
              from, profile, {'displayPhoneNumber': text});
          await _sendWhatsAppMessage(
              from, "Phone Number updated to '$text'! ✅");
        } catch (e) {
          print('Error updating phone number: $e');
          await _sendWhatsAppMessage(
              from, 'Failed to update phone number. Please try again.');
        }
        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppInteractiveList(
          from,
          'What else would you like to update? 👇',
          'View Options',
          'Edit Profile',
          [
            {'id': 'btn_edit_name', 'title': 'Business Name'},
            {'id': 'btn_edit_phone', 'title': 'Phone Number'},
            {'id': 'btn_edit_bank', 'title': 'Bank Details'},
            {'id': 'btn_edit_theme', 'title': 'Theme'},
            {'id': 'btn_edit_layout', 'title': 'Layout'},
            {'id': 'btn_edit_address', 'title': 'Business Address'},
          ],
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
        try {
          await _updateProfileAndOrg(from, profile, {'businessAddress': text});
          await _sendWhatsAppMessage(from, "Address updated to '$text'! ✅");
        } catch (e) {
          print('Error updating address: $e');
          await _sendWhatsAppMessage(
              from, 'Failed to update address. Please try again.');
        }
        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppInteractiveList(
          from,
          'What else would you like to update? 👇',
          'View Options',
          'Edit Profile',
          [
            {'id': 'btn_edit_name', 'title': 'Business Name'},
            {'id': 'btn_edit_phone', 'title': 'Phone Number'},
            {'id': 'btn_edit_bank', 'title': 'Bank Details'},
            {'id': 'btn_edit_theme', 'title': 'Theme'},
            {'id': 'btn_edit_layout', 'title': 'Layout'},
            {'id': 'btn_edit_address', 'title': 'Business Address'},
          ],
        );
      } else {
        await _sendWhatsAppMessage(
          from,
          'Please send text for the address.',
        );
      }
      break;

    case UserAction.editLogo:
      if (type == 'image' || type == 'document') {
        try {
          final mediaId = type == 'image'
              ? messageData['image']['id']
              : messageData['document']['id'];
          final tempUrl = await _getWhatsAppMediaUrl(mediaId as String);

          final bytes = await _downloadFileBytes(tempUrl);
          final publicUrl = await _firestoreService.uploadFile(
            'logos/$from.jpg',
            bytes,
            'image/jpeg',
          );
          await _sendWhatsAppMessage(from, 'Saving Logo...... ');
          await _updateProfileAndOrg(from, profile, {'logoUrl': publicUrl});
          await _sendWhatsAppMessage(from, 'Logo updated successfully! 🖼️');
        } catch (e) {
          print('Error updating logo: $e');
          await _sendWhatsAppMessage(
              from, 'Failed to save logo. Please try again.');
        }

        // LOOP BACK TO MENU
        await _firestoreService.updateAction(from, UserAction.editProfileMenu);
        await _sendWhatsAppInteractiveList(
          from,
          'What else would you like to update? 👇',
          'View Options',
          'Edit Profile',
          [
            {'id': 'btn_edit_name', 'title': 'Business Name'},
            {'id': 'btn_edit_phone', 'title': 'Phone Number'},
            {'id': 'btn_edit_bank', 'title': 'Bank Details'},
            {'id': 'btn_edit_theme', 'title': 'Theme'},
            {'id': 'btn_edit_layout', 'title': 'Layout'},
            {'id': 'btn_edit_address', 'title': 'Business Address'},
          ],
        );
      } else {
        await _sendWhatsAppMessage(from, 'Please send an image or document.');
      }
      break;

    case UserAction.idle:
      // CONVERSATIONAL ROUTER

      try {
        final intentResult = await _geminiService.determineUserIntent(text);

        switch (intentResult.type) {
          case UserIntent.chat:
            if (intentResult.response != null) {
              await _sendWhatsAppMessage(from, intentResult.response!);
            } else {
              await _sendWhatsAppMessage(from,
                  "I'm here to help! Would you like to create a receipt or invoice?");
            }
            break;

          case UserIntent.createReceipt:
            await _processReceiptResult(from, text, profile, isInvoice: false);
            break;

          case UserIntent.createInvoice:
            await _processReceiptResult(from, text, profile, isInvoice: true);
            break;

          case UserIntent.help:
            await _sendHelpMessage(from);
            break;

          case UserIntent.unknown:
            // Relaxed Fallback: If intent is unknown but text is long, try parsing.
            if (text.length > 20) {
              await _processReceiptResult(from, text, profile,
                  isInvoice: false);
            } else {
              await _sendWhatsAppMessage(from,
                  "I didn't quite catch that. You can type 'Menu' to see options or just tell me what you sold!");
            }
            break;
        }
      } catch (e) {
        print('Router Error: $e');
        await _sendWhatsAppMessage(from,
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

  if (lower.contains('create receipt') || lower == 'btn_create_receipt') {
    await _firestoreService.updateAction(from, UserAction.createReceipt);
    await _sendWhatsAppMessage(
      from,
      'Please provide the receipt details:\n\n- Customer Name\n- Items Bought & Prices\n- Tax (optional)\n- Customer Address (optional)\n- Customer Phone Number (optional)\n\nType *Cancel* to exit.',
    );
    return true;
  }

  if (lower.contains('create invoice') || lower == 'btn_create_invoice') {
    await _firestoreService.updateAction(from, UserAction.createInvoice);
    // Check if bank details exist
    final hasBankDetails =
        profile.bankName != null && profile.accountNumber != null;
    if (hasBankDetails) {
      await _sendWhatsAppMessage(
        from,
        'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Tax (optional)\n- Due Date (optional)\n- Client Address (optional)\n- Client Phone Number (optional)\n\nType *Cancel* to exit.',
      );
    } else {
      await _sendWhatsAppMessage(
        from,
        'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Tax (optional)\n- Due Date\n\n⚠️ **Also, please include your Bank Details (Bank Name, Account Number, Name) to save for future invoices.**\n\nType *Cancel* to exit.',
      );
    }
    return true;
  }

  if (lower == 'settings' ||
      lower == 'btn_settings' ||
      lower == '⚙️ settings') {
    if (profile.role != UserRole.admin) {
      await _sendWhatsAppMessage(
        from,
        'Only Admins can access settings.',
      );
      return true;
    }
    await _sendWhatsAppInteractiveList(
      from,
      '⚙️ *Settings Menu*\nWhat would you like to configure? 👇',
      'View Options',
      'Settings',
      [
        {
          'id': 'btn_edit_profile',
          'title': 'Edit Profile',
          'description': 'Update business details'
        },
        {
          'id': 'btn_invite_team',
          'title': 'Invite Team Member',
          'description': 'Share access with staff'
        },
        {
          'id': 'help',
          'title': 'Help & Support',
          'description': 'View guide or contact'
        },
      ],
    );
    return true;
  }

  if (lower == 'edit profile' || lower == 'btn_edit_profile') {
    if (profile.role != UserRole.admin) {
      await _sendWhatsAppMessage(
        from,
        'Only Admins can edit the business profile.',
      );
      return true;
    }
    await _firestoreService.updateAction(from, UserAction.editProfileMenu);
    await _sendWhatsAppInteractiveList(
      from,
      'What would you like to update? 👇',
      'View Options',
      'Edit Profile',
      [
        {
          'id': 'btn_edit_name',
          'title': 'Business Name',
          'description': 'Change your company name'
        },
        {
          'id': 'btn_edit_phone',
          'title': 'Phone Number',
          'description': 'Change contact number'
        },
        {
          'id': 'btn_edit_bank',
          'title': 'Bank Details',
          'description': 'Update payment info'
        },
        {
          'id': 'btn_edit_theme',
          'title': 'Theme (Color)',
          'description': 'Change receipt colors'
        },
        {
          'id': 'btn_edit_layout',
          'title': 'Layout Structure',
          'description': 'Change receipt design'
        },
        {
          'id': 'btn_edit_address',
          'title': 'Business Address',
          'description': 'Update location'
        },
        {
          'id': 'btn_edit_logo',
          'title': 'Upload Logo',
          'description': 'Update business logo'
        },
        {
          'id': 'btn_change_currency',
          'title': 'Change Currency',
          'description': 'Update default currency'
        },
      ],
    );
    return true;
  }

  if (lower == 'invite team member' || lower == 'btn_invite_team') {
    if (profile.role != UserRole.admin) {
      await _sendWhatsAppMessage(
        from,
        'Only Admins can invite team members.',
      );
      return true;
    }

    if (profile.orgId != null) {
      final org = await _firestoreService.getOrganization(profile.orgId!);
      if (org != null) {
        await _sendWhatsAppMessage(
          from,
          'Your Team Invite Code is:\n\n*${org.inviteCode}*\n\nShare this code with your team members so they can join your organization.',
        );
      } else {
        await _sendWhatsAppMessage(
          from,
          'Your organization could not be found. Please contact support.',
        );
      }
    } else {
      await _sendWhatsAppMessage(
        from,
        'You are not currently part of an organization. Please recreate your profile to get an invite code.',
      );
    }

    return true;
  }

  if (lower == 'change currency' || lower == 'btn_change_currency') {
    await _firestoreService.updateAction(from, UserAction.selectCurrency);

    const currencies = CountryUtils.supportedCurrencies;
    String message = 'Select your currency:\n\n';
    for (int i = 0; i < currencies.length; i++) {
      message +=
          '${i + 1}️⃣ ${currencies[i]['code']} (${currencies[i]['symbol']}) - ${currencies[i]['name']}\n';
    }
    message += '\nReply with the number, or type *Cancel* to exit.';

    await _sendWhatsAppMessage(from, message);
    return true;
  }

  if (lower == 'upload logo' || lower == 'btn_edit_logo') {
    if (profile.role != UserRole.admin) {
      await _sendWhatsAppMessage(
        from,
        'Only Admins can upload the business logo.',
      );
      return true;
    }
    await _firestoreService.updateAction(from, UserAction.editLogo);
    await _sendWhatsAppMessage(from,
        'Okay, send me the **New Logo Image**.\n\n⚠️ *If your logo has a transparent background, upload it as a Document so WhatsApp keeps it transparent!*\n\nType *Cancel* to exit.');
    return true;
  }

  if (lower.startsWith('cancel') ||
      lower == 'exit' ||
      lower.startsWith('quit')) {
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
  // Conversational filter: prevent chatting during document generation phase
  if (text.length < 100) {
    try {
      final intentResult = await _geminiService.determineUserIntent(text);
      if (intentResult.type == UserIntent.chat) {
        await _sendWhatsAppMessage(
            from,
            intentResult.response ??
                "Please provide the document details, or type 'Cancel' to exit.");
        return;
      } else if (intentResult.type == UserIntent.help) {
        await _sendHelpMessage(from);
        return;
      }
    } catch (_) {
      // Ignore intent failure and proceed
    }
  }

  await _sendWhatsAppMessage(
    from,
    'Generating ${isInvoice ? "Invoice" : "Receipt"}... ⏳',
  );

  print(
      'DEBUG: Processing receipt with Currency: ${profile.currencyCode} (${profile.currencySymbol})');

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

    // Phase B check: Handle missing bank details for Invoices
    if (isInvoice) {
      final hasBankDetails =
          profile.bankName != null && profile.accountNumber != null;
      if (!hasBankDetails) {
        await _firestoreService.updateProfileData(from, {
          'pendingTransaction': jsonEncode(transaction.toJson()),
          'currentAction': UserAction.awaitingInvoiceBankDetails.name,
        });

        await _sendWhatsAppMessage(
          from,
          "I have your invoice details ready! However, you haven't added your payment/bank details to your profile yet.\n\nPlease reply with your **Bank Name, Account Number, and Account Name** so I can add them to this invoice and save them for next time.\n\nType *Cancel* to exit.",
        );
        return; // Pause flow here
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

    await _sendWhatsAppInteractiveButtons(
      from,
      "Got it! 🧾\n\nSelect a style for your ${isInvoice ? 'Invoice' : 'Receipt'}:",
      [
        {'id': 'theme_classic', 'title': 'B&W (Classic)'},
        {'id': 'theme_beige', 'title': 'Beige'},
      ],
    );
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

  final lower = body.toLowerCase().trim();
  if (lower == 'theme_classic' ||
      lower == '1' ||
      lower == 'classic' ||
      lower == 'b&w (classic)') {
    themeIndex = 0;
  } else if (lower == 'theme_beige' || lower == '2' || lower == 'beige') {
    themeIndex = 1;
  }

  if (themeIndex == null) {
    await _sendWhatsAppMessage(
      from,
      'Please select an option from the menu, or reply with Classic or Beige.',
    );
    return;
  }

  // Update Profile with new theme preference
  await _updateProfileAndOrg(from, profile, {'themeIndex': themeIndex});
  profile = profile.copyWith(themeIndex: themeIndex);

  // If no pending transaction, this was just a profile update
  if (profile.pendingTransaction == null) {
    await _sendWhatsAppMessage(from, 'Default theme updated! ✅');
    // Go back to profile menu
    await _firestoreService.updateAction(from, UserAction.editProfileMenu);
    await _sendWhatsAppInteractiveList(
        from,
        'What else would you like to update? 👇',
        'View Options',
        'Edit Profile', [
      {'id': 'btn_edit_name', 'title': 'Business Name'},
      {'id': 'btn_edit_phone', 'title': 'Phone Number'},
      {'id': 'btn_edit_bank', 'title': 'Bank Details'},
      {'id': 'btn_edit_theme', 'title': 'Theme'},
      {'id': 'btn_edit_layout', 'title': 'Layout'},
      {'id': 'btn_edit_address', 'title': 'Business Address'},
    ]);
    return;
  }

  // Otherwise, continue to generate the pending receipt
  await _generateAndSendPDF(
      from, profile, profile.pendingTransaction!, themeIndex);
}

Future<void> _handleLayoutSelection(
  String from,
  String body,
  BusinessProfile profile,
) async {
  int? layoutIndex;

  final lower = body.toLowerCase().trim();
  if (lower == '1' || lower == 'classic') {
    layoutIndex = 0;
  } else if (lower == '2' || lower == 'modern' || lower == 'circle') {
    layoutIndex = 1;
  } else if (lower == '3' || lower == 'minimal' || lower == 'grid') {
    layoutIndex = 2;
  } else if (lower == '4' || lower == 'standard' || lower == 'premium') {
    layoutIndex = 3;
  }

  if (layoutIndex == null) {
    await _sendWhatsAppMessage(
      from,
      'Please reply with 1, 2, 3, or 4 to select a layout structure.',
    );
    return;
  }

  // Update Profile with new layout preference
  await _updateProfileAndOrg(from, profile, {'layoutIndex': layoutIndex});
  profile = profile.copyWith(layoutIndex: layoutIndex);

  // If no pending transaction, this was just a profile update
  if (profile.pendingTransaction == null) {
    await _sendWhatsAppMessage(from, 'Default layout updated! ✅');
    // Go back to profile menu
    await _firestoreService.updateAction(from, UserAction.editProfileMenu);
    await _sendWhatsAppInteractiveList(
        from,
        'What else would you like to update? 👇',
        'View Options',
        'Edit Profile', [
      {'id': 'btn_edit_name', 'title': 'Business Name'},
      {'id': 'btn_edit_phone', 'title': 'Phone Number'},
      {'id': 'btn_edit_bank', 'title': 'Bank Details'},
      {'id': 'btn_edit_theme', 'title': 'Theme'},
      {'id': 'btn_edit_layout', 'title': 'Layout'},
      {'id': 'btn_edit_address', 'title': 'Business Address'},
    ]);
    return;
  }

  await _generateAndSendPDF(
      from, profile, profile.pendingTransaction!, profile.themeIndex ?? 0);
}

Future<void> _generateAndSendPDF(
  String from,
  BusinessProfile profile,
  Transaction transaction,
  int themeIndex,
) async {
  await _sendWhatsAppMessage(from, 'Generating PDF... ⏳');

  try {
    Organization? org;
    if (profile.orgId != null) {
      org = await _firestoreService.getOrganization(profile.orgId!);
    }

    final pdfBytes = await _pdfService.generateReceipt(
      profile, // Still passing profile as fallback/context
      transaction,
      themeIndex: themeIndex,
      layoutIndex: profile.layoutIndex ?? 0,
      org: org,
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
    await _sendWhatsAppDocument(from, pdfUrl, fileName);

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
  String mediaType, {
  String? caption,
}) async {
  final url =
      Uri.parse('https://graph.facebook.com/v17.0/$_phoneNumberId/messages');
  final headers = {
    'Authorization': 'Bearer $_whatsappToken',
    'Content-Type': 'application/json',
  };

  final Map<String, dynamic> mediaPayload = {
    'link': mediaUrl,
  };

  if (caption != null) {
    mediaPayload['caption'] = caption;
  }

  final body = jsonEncode({
    'messaging_product': 'whatsapp',
    'to': to,
    'type': mediaType,
    mediaType: mediaPayload,
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

Future<void> _sendWhatsAppDocument(
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
    },
  });

  try {
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode != 200) {
      print('Failed to send WhatsApp document: ${response.body}');
    }
  } catch (e) {
    print('Error sending WhatsApp document: $e');
  }
}

Future<void> _sendWhatsAppInteractiveButtons(
  String to,
  String bodyText,
  List<Map<String, String>> buttons,
) async {
  final url =
      Uri.parse('https://graph.facebook.com/v17.0/$_phoneNumberId/messages');
  final headers = {
    'Authorization': 'Bearer $_whatsappToken',
    'Content-Type': 'application/json',
  };

  final actionButtons = buttons.map((b) {
    return {
      'type': 'reply',
      'reply': {
        'id': b['id'],
        'title': b['title'],
      }
    };
  }).toList();

  final body = jsonEncode({
    'messaging_product': 'whatsapp',
    'to': to,
    'type': 'interactive',
    'interactive': {
      'type': 'button',
      'body': {'text': bodyText},
      'action': {
        'buttons': actionButtons,
      }
    }
  });

  try {
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode != 200) {
      print('Failed to send interactive buttons: ${response.body}');
    }
  } catch (e) {
    print('Error sending interactive buttons: $e');
  }
}

Future<void> _sendWhatsAppInteractiveList(
  String to,
  String bodyText,
  String buttonText,
  String listTitle,
  List<Map<String, String>> rows,
) async {
  final url =
      Uri.parse('https://graph.facebook.com/v17.0/$_phoneNumberId/messages');
  final headers = {
    'Authorization': 'Bearer $_whatsappToken',
    'Content-Type': 'application/json',
  };

  final listRows = rows.map((r) {
    return {
      'id': r['id'],
      'title': r['title'],
      if (r['description'] != null) 'description': r['description'],
    };
  }).toList();

  final body = jsonEncode({
    'messaging_product': 'whatsapp',
    'to': to,
    'type': 'interactive',
    'interactive': {
      'type': 'list',
      'body': {'text': bodyText},
      'action': {
        'button': buttonText,
        'sections': [
          {
            'title': listTitle,
            'rows': listRows,
          }
        ]
      }
    }
  });

  try {
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode != 200) {
      print('Failed to send interactive list: ${response.body}');
    }
  } catch (e) {
    print('Error sending interactive list: $e');
  }
}

Future<void> _sendWelcomeMessage(String to, BusinessProfile profile) async {
  await _firestoreService.updateAction(to, UserAction.idle);

  const String bodyText = 'Hey! What can I do for you? 🙋‍♂️\n\n'
      '_Or just send me the details of a sale to quickly generate a receipt!_';

  final List<Map<String, String>> buttons = [
    {'id': 'btn_create_receipt', 'title': '🧾 Receipt'},
    {'id': 'btn_create_invoice', 'title': '📄 Invoice'},
  ];

  if (profile.role == UserRole.admin) {
    buttons.add({'id': 'btn_settings', 'title': '⚙️ Settings'});
  } else {
    buttons.add({'id': 'help', 'title': '❓ Help'});
  }

  await _sendWhatsAppInteractiveButtons(to, bodyText, buttons);
}

Future<void> _sendHelpMessage(String to) async {
  await _sendWhatsAppMessage(
    to,
    '''
*How to use Remi* 🤖🧾

I can help you create professional Receipts and Invoices quickly!

*1. Create a Receipt*
Simply type the details of the sale.
Example: *"Sold 2 pairs of shoes for 15k each and a t-shirt for 5000 to John Doe"*
OR type *"Create Receipt"* to follow the steps. You can also include taxes!

*2. Create an Invoice*
Type *"Create Invoice"* to start. I'll ask for client details, items, tax, and due date.
(Make sure your Bank Details are set in your profile!)

*3. Edit Profile & Logo (Admins Only)*
Type *"Edit Profile"* or *"Menu"* to update your Business Name, Address, Phone, or Bank Details. Type *"Upload Logo"* to set your brand image.

*4. Invite Team Member (Admins Only)*
Type *"Invite Team Member"* to get your 6-character code. Your staff can use this to join your organization and generate receipts on your behalf.

*5. Image Parsing*
Send me a photo of a handwritten receipt or note, and I'll digitize it for you!

Type *"Menu"* to see all options or type *"Cancel"* to stop any current action.
Need more help? Contact support at woobackbigmlboa@gmail.com.
''',
  );
}

Future<void> _updateProfileAndOrg(
  String from,
  BusinessProfile profile,
  Map<String, dynamic> data,
) async {
  await _firestoreService.updateProfileData(from, data);
  if (profile.role == UserRole.admin && profile.orgId != null) {
    await _firestoreService.updateOrganizationData(profile.orgId!, data);
  }
}
