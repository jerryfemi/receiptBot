import 'package:receipt_bot/handlers/handlers.dart';
import 'package:receipt_bot/handlers/stats_handler.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/gemini_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/constants.dart';
import 'package:receipt_bot/utils/country_utils.dart';

class MessageRouter {
  final FirestoreService firestoreService;
  final OnboardingHandler onboardingHandler;
  final SettingsHandler settingsHandler;
  final ReceiptHandler receiptHandler;
  final SubscriptionHandler subscriptionHandler;
  final StatsHandler statsHandler;
  final GeminiService geminiService;
  final WhatsAppService whatsappService;

  MessageRouter({
    required this.firestoreService,
    required this.onboardingHandler,
    required this.settingsHandler,
    required this.receiptHandler,
    required this.subscriptionHandler,
    required this.statsHandler,
    required this.geminiService,
    required this.whatsappService,
  });

  Future<void> routeMessage({
    required String phoneNumber,
    required String text,
    required String type,
    required Map<String, dynamic> messageData,
    required BusinessProfile profile,
  }) async {
    print('--- Handling message from $phoneNumber ---');
    print('Text: $text');

    try {
      // State Machine
      switch (profile.status ?? OnboardingStatus.new_user) {
        case OnboardingStatus.new_user:
          await onboardingHandler.handleNewUser(phoneNumber);
          break;

        case OnboardingStatus.awaiting_setup_choice:
          await onboardingHandler.handleSetupChoice(phoneNumber, text);
          break;

        case OnboardingStatus.awaiting_invite_code:
          await onboardingHandler.handleInviteCode(phoneNumber, text);
          break;

        case OnboardingStatus.awaiting_address:
          // Here `text` is the businessName provided
          await onboardingHandler.handleBusinessName(phoneNumber, text);
          break;

        case OnboardingStatus.awaiting_phone:
          await onboardingHandler.handleBusinessAddress(phoneNumber, text, profile);
          break;

        case OnboardingStatus.awaiting_logo:
          await onboardingHandler.handleOnboardingLogo(phoneNumber, text, type, messageData, profile);
          break;

        case OnboardingStatus.active:
          await _handleActiveUser(phoneNumber, text, type, messageData, profile);
          break;
      }
    } catch (e) {
      print('Error in routeMessage: $e');
      // If we fail outside the state machine (e.g. Firestore error)
      await whatsappService.sendMessage(phoneNumber, 'System Error: $e');
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
        await receiptHandler.processImageReceipt(from, messageData, profile);
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
        await receiptHandler.processReceiptResult(from, text, profile, isInvoice: false);
        break;
      case UserAction.createInvoice:
        await receiptHandler.processReceiptResult(from, text, profile, isInvoice: true);
        break;
      case UserAction.selectLayout:
        await receiptHandler.handleLayoutSelection(from, text, profile);
        break;
      case UserAction.selectingSubscriptionPlan:
        await subscriptionHandler.handlePlanSelection(from, text, profile);
        break;

      case UserAction.awaitingEmailForUpgrade:
        await subscriptionHandler.handleEmailForUpgrade(from, text, profile);
        break;
      case UserAction.removeTeamMember:
        await settingsHandler.handleRemoveTeamMember(from, text);
        break;
      case UserAction.confirmRemoveTeamMember:
        await settingsHandler.handleConfirmRemoveTeamMember(from, text);
        break;

      case UserAction.editProfileMenu:
        await settingsHandler.handleEditProfileMenuSelection(from, text, profile);
        break;

      case UserAction.selectCurrency:
        await settingsHandler.handleCurrencySelection(from, text, profile);
        break;

      case UserAction.editBankDetails:
        await settingsHandler.handleEditBankDetails(from, text, profile);
        break;

      case UserAction.awaitingInvoiceBankDetails:
        await receiptHandler.handleInvoiceBankDetails(from, text, profile);
        break;

      case UserAction.selectTheme:
        await receiptHandler.handleThemeSelection(from, text, profile);
        break;

      case UserAction.editName:
        await settingsHandler.handleEditName(from, text, type, profile);
        break;

      case UserAction.editPhone:
        await settingsHandler.handleEditPhone(from, text, type, profile);
        break;

      case UserAction.editAddress:
        await settingsHandler.handleEditAddress(from, text, type, profile);
        break;

      case UserAction.editLogo:
        await settingsHandler.handleEditLogo(from, type, messageData, profile);
        break;

      case UserAction.idle:
        // CONVERSATIONAL ROUTER - Let Gemini decide what the user wants

        try {
          final intentResult = await geminiService.determineUserIntent(text);

          switch (intentResult.type) {
            case UserIntent.chat:
              // Casual conversation - just respond
              await whatsappService.sendMessage(
                from,
                intentResult.response ?? "I'm here to help! Type 'Menu' to see what I can do.",
              );
              break;

            case UserIntent.help:
              await _sendHelpMessage(from);
              break;

            case UserIntent.wantsReceipt:
              // User wants to create receipt but hasn't given details yet
              // Send encouraging response and start guided flow
              await firestoreService.updateAction(from, UserAction.createReceipt);
              await whatsappService.sendMessage(
                from,
                intentResult.response ??
                    "Great! Tell me the sale details:\n\n*Customer name, items bought, and prices*\n\nExample: _John bought 2 shoes for 15k each and a bag for 8000_\n\nType *Cancel* to exit.",
              );
              break;

            case UserIntent.wantsInvoice:
              // User wants to create invoice but hasn't given details yet
              await firestoreService.updateAction(from, UserAction.createInvoice);
              final hasBankDetails = profile.bankName != null && profile.accountNumber != null;
              if (hasBankDetails) {
                await whatsappService.sendMessage(
                  from,
                  intentResult.response ??
                      "Let's create that invoice! Tell me:\n\n*Client name, items, prices, and due date*\n\nType *Cancel* to exit.",
                );
              } else {
                await whatsappService.sendMessage(
                  from,
                  intentResult.response ??
                      "Let's create that invoice! Tell me:\n\n*Client name, items, prices*\n\n⚠️ Also include your *Bank Details* so clients know where to pay.\n\nType *Cancel* to exit.",
                );
              }
              break;

            case UserIntent.hasReceiptData:
              // User provided actual receipt data - parse it!
              await receiptHandler.processReceiptResult(from, text, profile, isInvoice: false);
              break;

            case UserIntent.hasInvoiceData:
              // User provided actual invoice data - parse it!
              await receiptHandler.processReceiptResult(from, text, profile, isInvoice: true);
              break;

            case UserIntent.getStats:
              // Send the friendly AI response first
              if (intentResult.response != null) {
                await whatsappService.sendMessage(from, intentResult.response!);
              }
              await statsHandler.showStatsMenu(from);
              break;

            case UserIntent.checkSubscription:
              if (intentResult.response != null) {
                await whatsappService.sendMessage(from, intentResult.response!);
              }
              await subscriptionHandler.showSubscriptionStatus(from, profile);
              break;

            case UserIntent.settings:
              if (intentResult.response != null) {
                await whatsappService.sendMessage(from, intentResult.response!);
              }
              await settingsHandler.showSettingsMenu(from, profile.isPremium);
              break;

            case UserIntent.question:
              // User is asking a general question - respond with the AI's answer
              if (intentResult.response != null) {
                await whatsappService.sendMessage(from, intentResult.response!);
              } else {
                // Fallback for questions we can't answer
                await whatsappService.sendMessage(
                  from,
                  "I'm not sure about that. Type *Menu* to see your options, or *Help* for instructions!",
                );
              }
              break;

            case UserIntent.unknown:
              // Truly unknown - be helpful
              await whatsappService.sendMessage(
                from,
                "I'm not sure what you mean. 🤔\n\nYou can:\n• Tell me what you sold to generate a receipt\n• Type *Menu* to see options\n• Type *Help* for instructions",
              );
              break;
          }
        } catch (e) {
          print('Router Error: $e');
          await whatsappService.sendMessage(
              from, "I'm having a little trouble thinking right now. 😵‍💫 Please try again!");
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
    // ===========================================================================
    // INTERACTIVE BUTTON OVERRIDES (highest priority)
    // Intercept button payloads REGARDLESS of current state to prevent
    // stale-button collisions when users click old interactive messages.
    // ===========================================================================
    if (lower.startsWith('btn_') || lower.startsWith('theme_')) {
      final handled = await _handleButtonOverride(from, lower, originalText, profile);
      if (handled) return true;
    }

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
      await subscriptionHandler.showUpgradeMenu(from, profile);
      return true;
    }

    // Handle Subscription Status check
    if (lower == ButtonIds.subStatus || lower == '💎 subscription status') {
      await subscriptionHandler.showSubscriptionStatus(from, profile);
      return true;
    }

    if (lower == 'verify payment' || lower == ButtonIds.verifyPayment) {
      await subscriptionHandler.handleVerifyPayment(from, profile);
      return true;
    }

    if (lower.contains('create receipt') || lower == ButtonIds.createReceipt) {
      await firestoreService.updateAction(from, UserAction.createReceipt);
      await whatsappService.sendMessage(
        from,
        'Please provide the receipt details:\n\n- Customer Name\n- Items Bought & Prices\n- Tax (optional)\n- Customer Address (optional)\n- Customer Phone Number (optional)\n\nType *Cancel* to exit.',
      );
      return true;
    }

    if (lower.contains('create invoice') || lower == ButtonIds.createInvoice) {
      await firestoreService.updateAction(from, UserAction.createInvoice);
      // Check if bank details exist
      final hasBankDetails = profile.bankName != null && profile.accountNumber != null;
      if (hasBankDetails) {
        await whatsappService.sendMessage(
          from,
          'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Tax (optional)\n- Due Date (optional)\n- Client Address (optional)\n- Client Phone Number (optional)\n\nType *Cancel* to exit.',
        );
      } else {
        await whatsappService.sendMessage(
          from,
          'Please provide the INVOICE details:\n\n- Client Name\n- Items & Prices\n- Tax (optional)\n- Due Date\n\n⚠️ **Also, please include your Bank Details (Bank Name, Account Number, Name) to save for future invoices.**\n\nType *Cancel* to exit.',
        );
      }
      return true;
    }

    if (lower == 'settings' || lower == ButtonIds.settings || lower == '⚙️ settings') {
      if (profile.role != UserRole.admin) {
        await whatsappService.sendMessage(from, 'Only Admins can access settings.');
        return true;
      }
      await settingsHandler.showSettingsMenu(from, profile.isPremium);
      return true;
    }

    if (lower == 'edit profile' || lower == ButtonIds.editProfile) {
      if (profile.role != UserRole.admin) {
        await whatsappService.sendMessage(from, 'Only Admins can edit the business profile.');
        return true;
      }
      await firestoreService.updateAction(from, UserAction.editProfileMenu);
      await settingsHandler.showEditProfileMenu(from);
      return true;
    }

    if (lower == 'manage team' || lower == ButtonIds.manageTeam) {
      if (profile.role != UserRole.admin) {
        await whatsappService.sendMessage(from, 'Only Admins can manage team members.');
        return true;
      }
      await settingsHandler.showTeamManagement(from, profile);
      return true;
    }

    if (lower == 'stats' || lower == ButtonIds.stats || lower.contains('view stats')) {
      if (!profile.isPremium) {
        await whatsappService.sendMessage(from,
            '⭐️ *Premium Feature*\n\nSales Stats and Business Intelligence is available on our Premium plan. Upgrade to view your Daily, Weekly, and Monthly performance charts!');
        await subscriptionHandler.showUpgradeMenu(from, profile);
        return true;
      }
      await statsHandler.showStatsMenu(from);
      return true;
    }

    if (lower == 'upload logo' || lower == ButtonIds.editLogo) {
      if (profile.role != UserRole.admin) {
        await whatsappService.sendMessage(from, 'Only Admins can upload the business logo.');
        return true;
      }
      await firestoreService.updateAction(from, UserAction.editLogo);
      await whatsappService.sendMessage(from,
          'Okay, send me the *New Logo Image*.\n\n⚠️ *If your logo has a transparent background, upload it as a Document so WhatsApp keeps it transparent!*\n\nType *Back* to return or *Cancel* to exit.');
      return true;
    }

    if (lower.startsWith('cancel') ||
        lower == ButtonIds.cancel ||
        lower == 'exit' ||
        lower.startsWith('quit')) {
      await firestoreService.updateAction(from, UserAction.idle);
      await whatsappService.sendMessage(from, 'Action cancelled.');
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
          await settingsHandler.showEditProfileMenu(from);
          return true;

        case UserAction.editProfileMenu:
        case UserAction.removeTeamMember:
        case UserAction.confirmRemoveTeamMember:
          // Return to Settings menu
          await settingsHandler.showSettingsMenu(from, profile.isPremium);
          return true;

        case UserAction.selectingSubscriptionPlan:
        case UserAction.awaitingEmailForUpgrade:
          // Return to Settings menu
          await settingsHandler.showSettingsMenu(from, profile.isPremium);
          return true;

        // ignore: no_default_cases
        default:
          // For other actions, just go idle
          await firestoreService.updateAction(from, UserAction.idle);
          await whatsappService.sendMessage(from, 'Returned to main menu.');
          return true;
      }
    }

    return false;
  }

  /// Handles interactive button payloads as global overrides.
  /// This ensures clicking old buttons always works, regardless of current state.
  Future<bool> _handleButtonOverride(
    String from,
    String lower,
    String originalText,
    BusinessProfile profile,
  ) async {
    switch (lower) {
      // -------------------------------------------------------------------------
      // PROFILE EDIT FIELD OVERRIDES (Admin only)
      // -------------------------------------------------------------------------
      case ButtonIds.editName:
        if (profile.role != UserRole.admin) {
          await whatsappService.sendMessage(from, 'Only Admins can edit the business profile.');
          return true;
        }
        await firestoreService.updateAction(from, UserAction.editName);
        await whatsappService.sendMessage(
          from,
          'Okay, send me the *New Business Name*.\n\nType *Back* to return or *Cancel* to exit.',
        );
        return true;

      case ButtonIds.editPhone:
        if (profile.role != UserRole.admin) {
          await whatsappService.sendMessage(from, 'Only Admins can edit the business profile.');
          return true;
        }
        await firestoreService.updateAction(from, UserAction.editPhone);
        await whatsappService.sendMessage(
          from,
          'Okay, send me the *New Phone Number*.\n\nType *Back* to return or *Cancel* to exit.',
        );
        return true;

      case ButtonIds.editBank:
        if (profile.role != UserRole.admin) {
          await whatsappService.sendMessage(from, 'Only Admins can edit the business profile.');
          return true;
        }
        await firestoreService.updateAction(from, UserAction.editBankDetails);
        await whatsappService.sendMessage(
          from,
          'Okay, send me your *Bank Details*:\n\nBank Name, Account Number, Account Name\n\nType *Back* to return or *Cancel* to exit.',
        );
        return true;

      case ButtonIds.editAddress:
        if (profile.role != UserRole.admin) {
          await whatsappService.sendMessage(from, 'Only Admins can edit the business profile.');
          return true;
        }
        await firestoreService.updateAction(from, UserAction.editAddress);
        await whatsappService.sendMessage(
          from,
          'Okay, send me the *New Business Address*.\n\nType *Back* to return or *Cancel* to exit.',
        );
        return true;

      case ButtonIds.editTheme:
        if (profile.role != UserRole.admin) {
          await whatsappService.sendMessage(from, 'Only Admins can edit the business profile.');
          return true;
        }
        await firestoreService.updateAction(from, UserAction.selectTheme);
        await whatsappService.sendInteractiveButtons(
          from,
          'Select a new *Theme (Color)*:',
          MenuOptions.themes,
        );
        return true;

      case ButtonIds.editLayout:
        if (profile.role != UserRole.admin) {
          await whatsappService.sendMessage(from, 'Only Admins can edit the business profile.');
          return true;
        }
        if (!profile.isPremium) {
          await whatsappService.sendInteractiveButtons(
            from,
            '💎 *Premium Feature*\n\nCustom layouts are only available for Premium users!',
            [
              {'id': ButtonIds.upgrade, 'title': '⭐ Upgrade'},
              {'id': ButtonIds.back, 'title': '⬅ Back'},
            ],
          );
          return true;
        }
        await settingsHandler.showLayoutSelection(from);
        return true;

      case ButtonIds.changeCurrency:
        if (profile.role != UserRole.admin) {
          await whatsappService.sendMessage(from, 'Only Admins can edit the business profile.');
          return true;
        }
        await settingsHandler.showCurrencySelection(from);
        return true;

      case ButtonIds.editLogo:
        if (profile.role != UserRole.admin) {
          await whatsappService.sendMessage(from, 'Only Admins can upload the business logo.');
          return true;
        }
        await firestoreService.updateAction(from, UserAction.editLogo);
        await whatsappService.sendMessage(
          from,
          'Okay, send me the *New Logo Image*.\n\n⚠️ *If your logo has a transparent background, upload it as a Document so WhatsApp keeps it transparent!*\n\nType *Back* to return or *Cancel* to exit.',
        );
        return true;

      // -------------------------------------------------------------------------
      // STATS OVERRIDES
      // -------------------------------------------------------------------------
      case ButtonIds.statsWeekly:
      case ButtonIds.statsMonthly:
      case ButtonIds.statsYearly:
      case ButtonIds.statsAllTime:
        if (!profile.isPremium) {
          await whatsappService.sendMessage(from,
              '⭐️ *Premium Feature*\n\nSales Stats and Business Intelligence is available on our Premium plan. Upgrade to view your Daily, Weekly, Monthly, Yearly, and All Time performance charts!');
          await subscriptionHandler.showUpgradeMenu(from, profile);
          return true;
        }
        final timeframe = lower.replaceAll('btn_stats_', '');
        await statsHandler.processStatsRequest(from, timeframe, profile);
        return true;

      // -------------------------------------------------------------------------
      // LAYOUT OVERRIDES — call handler directly (one-shot, no pending state)
      // -------------------------------------------------------------------------
      case ButtonIds.layoutCorporate:
      case ButtonIds.layoutSignature:
      case ButtonIds.layoutSimple:
      case ButtonIds.layoutLegacy:
        await receiptHandler.handleLayoutSelection(from, originalText, profile);
        return true;

      // -------------------------------------------------------------------------
      // THEME OVERRIDES — call handler directly (one-shot, no pending state)
      // -------------------------------------------------------------------------
      case ButtonIds.themeClassic:
      case ButtonIds.themeBeige:
        await receiptHandler.handleThemeSelection(from, originalText, profile);
        return true;

      default:
        return false;
    }
  }

  Future<void> _sendWelcomeMessage(String to, BusinessProfile profile) async {
    await firestoreService.updateAction(to, UserAction.idle);

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

    await whatsappService.sendInteractiveButtons(to, bodyText, buttons);
  }

  Future<void> _sendHelpMessage(String to) async {
    await whatsappService.sendMessage(
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

Need human help? Contact support at remireceiptbot@gmail.com
''',
    );
  }
}
