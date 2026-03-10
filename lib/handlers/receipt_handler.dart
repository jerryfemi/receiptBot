import 'dart:convert';
import 'dart:typed_data';

import 'package:receipt_bot/handlers/settings_handler.dart';
import 'package:receipt_bot/handlers/subscription_handler.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/gemini_service.dart';
import 'package:receipt_bot/services/pdf_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/constants.dart';

/// Handles receipt and invoice generation flows.
class ReceiptHandler {
  final FirestoreService firestoreService;
  final WhatsAppService whatsappService;
  final GeminiService geminiService;
  final PdfService pdfService;
  final SettingsHandler settingsHandler;
  final SubscriptionHandler subscriptionHandler;

  ReceiptHandler({
    required this.firestoreService,
    required this.whatsappService,
    required this.geminiService,
    required this.pdfService,
    required this.settingsHandler,
    required this.subscriptionHandler,
  });

  // ==========================================================
  // START RECEIPT/INVOICE FLOW
  // ==========================================================

  /// Starts the receipt creation flow.
  Future<void> startReceiptFlow(String from) async {
    await firestoreService.updateAction(from, UserAction.createReceipt);
    await whatsappService.sendMessage(
      from,
      'Please provide the receipt details:\n\n- Customer Name\n- Items Bought & Prices\n- Tax (optional)\n- Customer Address (optional)\n- Customer Phone Number (optional)\n\nType *Cancel* to exit.',
    );
  }

  /// Starts the invoice creation flow.
  Future<void> startInvoiceFlow(String from, BusinessProfile profile) async {
    await firestoreService.updateAction(from, UserAction.createInvoice);

    final hasBankDetails =
        profile.bankName != null && profile.accountNumber != null;

    if (hasBankDetails) {
      await whatsappService.sendMessage(
        from,
        'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Tax (optional)\n- Due Date (optional)\n- Client Address (optional)\n- Client Phone Number (optional)\n\nType *Cancel* to exit.',
      );
    } else {
      await whatsappService.sendMessage(
        from,
        'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Tax (optional)\n- Due Date\n\n⚠️ *Also, please include your Bank Details (Bank Name, Account Number, Name) to save for future invoices.*\n\nType *Cancel* to exit.',
      );
    }
  }

  // ==========================================================
  // PROCESS RECEIPT RESULT (TEXT INPUT)
  // ==========================================================

  /// Processes text input to create a receipt or invoice.
  Future<void> processReceiptResult(
    String from,
    String text,
    BusinessProfile profile, {
    required bool isInvoice,
  }) async {
    // For short messages in the receipt flow, check if user is chatting vs providing data
    if (text.length < 60) {
      try {
        final intentResult = await geminiService.determineUserIntent(text);

        // If they're chatting or asking questions, respond and wait for real data
        if (intentResult.type == UserIntent.chat) {
          await whatsappService.sendMessage(
            from,
            intentResult.response ??
                "I'm waiting for your ${isInvoice ? 'invoice' : 'receipt'} details! Please send the customer name, items, and prices. Type *Cancel* to exit.",
          );
          return;
        } else if (intentResult.type == UserIntent.help) {
          await _sendHelpMessage(from);
          return;
        } else if (intentResult.type == UserIntent.question) {
          await whatsappService.sendMessage(
            from,
            intentResult.response ??
                "Let me answer that after we finish your ${isInvoice ? 'invoice' : 'receipt'}! Send the details or type *Cancel* to exit.",
          );
          return;
        } else if (intentResult.type == UserIntent.wantsReceipt ||
            intentResult.type == UserIntent.wantsInvoice) {
          // They're repeating intent but still no data
          await whatsappService.sendMessage(
            from,
            "I'm ready! Just send me the details:\n\n*Customer name, items bought, and prices*\n\nExample: _John bought 2 shoes @ 15k, 1 bag 8000_",
          );
          return;
        }
        // hasReceiptData/hasInvoiceData - proceed to parsing below
      } catch (_) {
        // Ignore intent failure and proceed with parsing attempt
      }
    }

    // Freemium check
    if (!(await subscriptionHandler.checkFreemiumLimit(from, profile))) {
      return;
    }

    await whatsappService.sendMessage(
      from,
      'Generating ${isInvoice ? "Invoice" : "Receipt"}... ⏳',
    );

    print(
        'DEBUG: Processing receipt with Currency: ${profile.currencyCode} (${profile.currencySymbol})');

    try {
      // AI Parsing
      print('DEBUG: Starting Gemini Parse...');
      final swGemini = Stopwatch()..start();
      final transaction = await geminiService.parseTransaction(
        text,
        currencySymbol: profile.currencySymbol,
        currencyCode: profile.currencyCode,
      );
      swGemini.stop();
      print('DEBUG: Gemini Parse took ${swGemini.elapsedMilliseconds} ms');

      // Validate Transaction
      if (transaction.items.isEmpty && transaction.totalAmount == 0) {
        await whatsappService.sendMessage(
          from,
          "Hmm, I couldn't find specific items with prices in that message. 🤔\n\nTry something like:\n_\"John bought 2 shoes for 15k each and a bag for 8000\"_\n\nOr type *Cancel* to exit.",
        );
        return;
      }

      // Update profile with new bank details if found
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
          await firestoreService.updateProfileData(from, updates);
          profile = profile.copyWith(
            bankName: transaction.bankName ?? profile.bankName,
            accountNumber: transaction.accountNumber ?? profile.accountNumber,
            accountName: transaction.accountName ?? profile.accountName,
          );
        }
      }

      // Handle missing bank details for invoices
      if (isInvoice) {
        final hasBankDetails =
            profile.bankName != null && profile.accountNumber != null;
        if (!hasBankDetails) {
          await firestoreService.updateProfileData(from, {
            'pendingTransaction': jsonEncode(transaction.toJson()),
            'currentAction': UserAction.awaitingInvoiceBankDetails.name,
          });

          await whatsappService.sendMessage(
            from,
            "I have your invoice details ready! However, you haven't added your payment/bank details to your profile yet.\n\nPlease reply with your *Bank Name, Account Number, and Account Name* so I can add them to this invoice and save them for next time.\n\nType *Cancel* to exit.",
          );
          return;
        }
      }

      // If we have a theme preference, generate directly
      if (profile.themeIndex != null) {
        await generateAndSendPDF(
            from, profile, transaction, profile.themeIndex!);
        return;
      }

      // Save pending transaction and ask for theme
      await firestoreService.updateProfileData(from, {
        'pendingTransaction': jsonEncode(transaction.toJson()),
        'currentAction': UserAction.selectTheme.name,
      });

      await whatsappService.sendInteractiveButtons(
        from,
        "Got it! 🧾\n\nSelect a style for your ${isInvoice ? 'Invoice' : 'Receipt'}:",
        MenuOptions.themes,
      );
    } catch (e) {
      print('Error generating receipt: $e');
      if (e.toString().contains('GEMINI_BUSY')) {
        await whatsappService.sendMessage(
          from,
          "Google's AI servers are currently taking a quick nap! 😴 Please wait a minute and try sending your receipt details again.",
        );
      } else {
        await whatsappService.sendMessage(
          from,
          "⚠️ Error: I couldn't process that.\n\nDetails: $e\n\nPlease try again or type 'Create Receipt' for help.",
        );
      }
    }
  }

  // ==========================================================
  // IMAGE SCANNING
  // ==========================================================

  /// Processes an uploaded image to create a receipt.
  Future<void> processImageReceipt(
    String from,
    Map<String, dynamic> messageData,
    BusinessProfile profile,
  ) async {
    // Freemium check
    if (!(await subscriptionHandler.checkFreemiumLimit(from, profile))) {
      return;
    }

    await whatsappService.sendMessage(from, "Scanning image... 🔎");

    try {
      // Get the image from WhatsApp
      final imageId = messageData['image']['id'] as String;
      final url = await whatsappService.getMediaUrl(imageId);
      final imageBytesList = await whatsappService.downloadFileBytes(url);
      final imageBytes = Uint8List.fromList(imageBytesList);

      // Send to Gemini Vision
      final transaction = await geminiService.parseImageTransaction(
        imageBytes,
        currencySymbol: profile.currencySymbol,
        currencyCode: profile.currencyCode,
      );

      // If user has saved theme preference, generate directly
      if (profile.themeIndex != null) {
        await generateAndSendPDF(
            from, profile, transaction, profile.themeIndex!);
        return;
      }

      // Save & Ask for Theme
      await firestoreService.updateProfileData(from, {
        'pendingTransaction': jsonEncode(transaction.toJson()),
        'currentAction': UserAction.selectTheme.name
      });

      await whatsappService.sendInteractiveButtons(
        from,
        "I found ${transaction.items.length} items totaling ${profile.currencySymbol}${transaction.totalAmount}!\n\nSelect a style:",
        [
          {'id': ButtonIds.themeClassic, 'title': 'Classic'},
          {'id': ButtonIds.themeBeige, 'title': 'Beige'},
        ],
      );
    } catch (e) {
      print("Image Scan Error: $e");
      if (e.toString().contains('GEMINI_BUSY')) {
        await whatsappService.sendMessage(from,
            "Google's AI servers are currently taking a quick nap! 😴 Please wait a minute and try sending your receipt image again.");
      } else {
        await whatsappService.sendMessage(from,
            "⚠️ I couldn't read that image clearly. Please try sending a clearer photo or type the details.");
      }
    }
  }

  // ==========================================================
  // THEME SELECTION FOR DOCUMENT
  // ==========================================================

  /// Handles theme selection during document generation.
  Future<void> handleThemeSelection(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    final themeIndex = settingsHandler.parseThemeSelection(text);

    if (themeIndex == null) {
      await whatsappService.sendMessage(
        from,
        'Please select an option from the menu, or reply with Classic or Beige.',
      );
      return;
    }

    // Update profile with theme preference
    await settingsHandler
        .updateProfileAndOrg(from, profile, {'themeIndex': themeIndex});
    profile = profile.copyWith(themeIndex: themeIndex);

    // If no pending transaction, this was just a profile update
    if (profile.pendingTransaction == null) {
      await settingsHandler.handleThemeSelectionForProfile(
          from, themeIndex, profile);
      return;
    }

    // Generate the pending receipt
    await generateAndSendPDF(
        from, profile, profile.pendingTransaction!, themeIndex);
  }

  // ==========================================================
  // LAYOUT SELECTION FOR DOCUMENT
  // ==========================================================

  /// Handles layout selection during document generation.
  Future<void> handleLayoutSelection(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    final layoutIndex = settingsHandler.parseLayoutSelection(text);

    if (layoutIndex == null) {
      await whatsappService.sendMessage(
        from,
        'Please select an option from the menu, or reply with 1, 2, 3, or 4.',
      );
      return;
    }

    // Update profile with layout preference
    await settingsHandler
        .updateProfileAndOrg(from, profile, {'layoutIndex': layoutIndex});
    profile = profile.copyWith(layoutIndex: layoutIndex);

    // If no pending transaction, this was just a profile update
    if (profile.pendingTransaction == null) {
      await settingsHandler.handleLayoutSelectionForProfile(
          from, layoutIndex, profile);
      return;
    }

    // Generate the pending receipt
    await generateAndSendPDF(
        from, profile, profile.pendingTransaction!, profile.themeIndex ?? 0);
  }

  // ==========================================================
  // HANDLE INVOICE BANK DETAILS
  // ==========================================================

  /// Handles bank details input during invoice flow.
  Future<void> handleInvoiceBankDetails(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    try {
      final transactionInfo = await geminiService.parseTransaction(text);

      if (transactionInfo.bankName != null) {
        await settingsHandler.updateProfileAndOrg(from, profile, {
          'bankName': transactionInfo.bankName,
          'accountNumber': transactionInfo.accountNumber,
          'accountName': transactionInfo.accountName,
        });

        profile = profile.copyWith(
          bankName: transactionInfo.bankName,
          accountNumber: transactionInfo.accountNumber,
          accountName: transactionInfo.accountName,
        );

        await whatsappService.sendMessage(from, 'Bank Details Saved! ✅');

        if (profile.pendingTransaction != null) {
          final pendingTx = profile.pendingTransaction!;

          if (profile.themeIndex != null) {
            await generateAndSendPDF(
              from,
              profile,
              pendingTx,
              profile.themeIndex!,
            );
          } else {
            await whatsappService.sendInteractiveButtons(
              from,
              "Got it! 🧾\n\nSelect a style for your Invoice:",
              MenuOptions.themes,
            );
            await firestoreService.updateAction(from, UserAction.selectTheme);
          }
        } else {
          await firestoreService.updateAction(from, UserAction.idle);
        }
      } else {
        await whatsappService.sendMessage(
          from,
          "I couldn't find bank details. Please try again (e.g. Bank, 0123456789, Name). Type *Cancel* to exit.",
        );
      }
    } catch (e) {
      if (e.toString().contains('GEMINI_BUSY')) {
        await whatsappService.sendMessage(
          from,
          "Google's AI servers are currently taking a quick nap! 😴 Please wait a minute and try again.",
        );
      } else {
        await whatsappService.sendMessage(
          from,
          'Error parsing details. Please try again.',
        );
      }
    }
  }

  // ==========================================================
  // PDF GENERATION
  // ==========================================================

  /// Generates and sends a PDF receipt/invoice.
  Future<void> generateAndSendPDF(
    String from,
    BusinessProfile profile,
    Transaction transaction,
    int themeIndex,
  ) async {
    try {
      // Fetch org in parallel with sending status message (if needed)
      final orgFuture = profile.orgId != null
          ? firestoreService.getOrganization(profile.orgId!)
          : Future.value(null);

      // Send status and fetch org in parallel
      await Future.wait([
        whatsappService.sendMessage(from, 'Generating PDF... ⏳'),
        orgFuture,
      ]);
      final org = await orgFuture;

      print('DEBUG: Starting PDF Generation...');
      final swPdf = Stopwatch()..start();
      final pdfBytes = await pdfService.generateReceipt(
        profile,
        transaction,
        themeIndex: themeIndex,
        layoutIndex: profile.layoutIndex ?? 3,
        org: org,
      );
      swPdf.stop();
      print('DEBUG: PDF generation took ${swPdf.elapsedMilliseconds} ms');

      // Upload PDF
      final fileName =
          '${transaction.type == TransactionType.invoice ? "invoice" : "receipt"}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      print('DEBUG: Starting Upload to Firebase Storage...');
      final swUpload = Stopwatch()..start();
      final pdfUrl = await firestoreService.uploadFile(
        'receipts/$from/$fileName',
        pdfBytes,
        'application/pdf',
      );
      swUpload.stop();
      print('DEBUG: Firebase upload took ${swUpload.elapsedMilliseconds} ms');

      // --- ADD SALES LEDGER ENTRY ---
      // We purposefully don't await this to speed up sending the receipt message!
      firestoreService
          .addSalesLedgerEntry(
        profile.orgId ?? from,
        fileName,
        transaction.customerName,
        transaction.transactionTotal,
        profile.currencyCode,
        transaction.date,
      )
          .catchError((e) {
        print('DEBUG: Failed to add ledger entry: $e');
      });

      // Send document directly (no extra "Here is your receipt" message)
      print('DEBUG: Sending WhatsApp Document...');
      final swSend = Stopwatch()..start();
      await whatsappService.sendDocument(from, pdfUrl, fileName);
      swSend.stop();
      print(
          'DEBUG: WhatsApp Document Send took ${swSend.elapsedMilliseconds} ms');

      // Handle freemium warning and clear pending in parallel
      await Future.wait([
        subscriptionHandler.handleFreemiumPostReceipt(from, profile),
        firestoreService.updateProfileData(from, {
          'pendingTransaction': '',
          'currentAction': UserAction.idle.name,
        }),
      ]);
    } catch (e, stackTrace) {
      print('Error generating PDF: $e\nStack trace:\n$stackTrace');
      await whatsappService.sendMessage(
        from,
        'Failed to generate PDF. Please try again.',
      );
      await firestoreService.updateAction(from, UserAction.idle);
    }
  }

  // ==========================================================
  // HELP MESSAGE
  // ==========================================================

  Future<void> _sendHelpMessage(String from) async {
    await whatsappService.sendMessage(
      from,
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
}
