import 'dart:io';

import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/lemon_squeezy_service.dart';
import 'package:receipt_bot/services/paystack_service.dart';
import 'package:receipt_bot/services/pdf_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/constants.dart';

/// Handles subscription, premium upgrades, and payment verification.
class SubscriptionHandler {
  final FirestoreService firestoreService;
  final WhatsAppService whatsappService;
  final PaystackService paystackService;
  final LemonSqueezyService lemonSqueezyService;
  final PdfService pdfService;

  SubscriptionHandler({
    required this.firestoreService,
    required this.whatsappService,
    required this.paystackService,
    required this.lemonSqueezyService,
    required this.pdfService,
  });

  // ==========================================================
  // UPGRADE MENU
  // ==========================================================

  /// Shows the upgrade/manage subscription menu.
  Future<void> showUpgradeMenu(String from, BusinessProfile profile) async {
    if (profile.role != UserRole.admin) {
      await whatsappService.sendMessage(
        from,
        'Only Admins can upgrade the business profile.',
      );
      return;
    }

    await firestoreService.updateAction(
        from, UserAction.selectingSubscriptionPlan);

    if (profile.isPremium) {
      await _showManageSubscriptionMenu(from, profile);
    } else {
      await _showNewSubscriptionMenu(from);
    }
  }

  Future<void> _showManageSubscriptionMenu(
    String from,
    BusinessProfile profile,
  ) async {
    final tierName = profile.pendingSubscriptionTier ?? "Premium";
    final expiry = profile.premiumExpiresAt;
    final dateStr = expiry != null
        ? "${expiry.day}/${expiry.month}/${expiry.year}"
        : "an unknown date";

    final isPaystack = CountryUtils.isPaystackRegion(from);

    if (tierName.toLowerCase() == 'annual') {
      // ANNUAL TIER: Only allow extension, no downgrade
      final desc = isPaystack
          ? 'Add 365 Days (₦${Pricing.annualNgn})'
          : r'Add 365 Days ($' '${Pricing.annualUsd})';

      await whatsappService.sendInteractiveList(
        from,
        '💎 *Manage Subscription*\n\nYou are currently on the *Annual Plan* (Valid until $dateStr).\n\nWould you like to extend your subscription for another year?',
        'View Options',
        'Select Option',
        [
          {
            'id': ButtonIds.yearly,
            'title': 'Extend Annual',
            'description': desc
          },
          {
            'id': ButtonIds.cancel,
            'title': 'Cancel',
            'description': 'Return to menu'
          }
        ],
      );
    } else {
      // MONTHLY TIER: Allow extension OR upgrade to Annual
      final monthlyDesc = isPaystack
          ? 'Add 30 Days (₦${Pricing.monthlyNgn})'
          : r'Add 30 Days ($' '${Pricing.monthlyUsd})';
      final annualDesc = isPaystack
          ? 'Save 20%! (₦${Pricing.annualNgn}/yr)'
          : r'Save $16! ($' '${Pricing.annualUsd}/yr)';

      await whatsappService.sendInteractiveList(
        from,
        '💎 *Manage Subscription*\n\nYou are currently on the *Monthly Plan* (Valid until $dateStr).\n\nWould you like to extend your month, or upgrade to Annual?',
        'View Options',
        'Select Option',
        [
          {
            'id': ButtonIds.monthly,
            'title': 'Extend Monthly',
            'description': monthlyDesc
          },
          {
            'id': ButtonIds.yearly,
            'title': 'Upgrade to Annual',
            'description': annualDesc
          },
          {
            'id': ButtonIds.cancel,
            'title': 'Cancel',
            'description': 'Return to menu'
          }
        ],
      );
    }
  }

  Future<void> _showNewSubscriptionMenu(String from) async {
    final isPaystack = CountryUtils.isPaystackRegion(from);
    final monthlyDesc = isPaystack
        ? 'Flexible (₦${Pricing.monthlyNgn}/mo)'
        : r'Flexible ($' '${Pricing.monthlyUsd}/mo)';
    final annualDesc = isPaystack
        ? 'Save 20%! (₦${Pricing.annualNgn}/yr)'
        : r'Save $16! ($' '${Pricing.annualUsd}/yr)';

    await whatsappService.sendInteractiveList(
      from,
      '💎 *Upgrade to Premium*\nUnlock pro layouts, Logo, and get monthly sales reports!\n\nSelect a plan below: 👇',
      'View Plans',
      'Select Plan',
      [
        {
          'id': ButtonIds.monthly,
          'title': 'Monthly Plan',
          'description': monthlyDesc
        },
        {
          'id': ButtonIds.yearly,
          'title': 'Annual Plan',
          'description': annualDesc
        },
        {
          'id': ButtonIds.cancel,
          'title': 'Cancel',
          'description': 'Return to menu'
        }
      ],
    );
  }

  // ==========================================================
  // PLAN SELECTION
  // ==========================================================

  /// Handles plan selection (monthly/yearly).
  Future<void> handlePlanSelection(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    final lower = text.toLowerCase().trim();

    if (lower != ButtonIds.monthly && lower != ButtonIds.yearly) {
      await whatsappService.sendMessage(from,
          "Please select a valid plan using the buttons provided, or type *Cancel* to exit.");
      return;
    }

    final plan = lower == ButtonIds.monthly ? 'monthly' : 'yearly';

    await firestoreService.updateProfileData(from, {
      'pendingSubscriptionTier': plan,
      'currentAction': UserAction.awaitingEmailForUpgrade.name,
    });

    final isPaystack = CountryUtils.isPaystackRegion(from);
    final gatewayName = isPaystack ? 'Paystack' : 'our secure checkout';
    final planLabel = plan == 'monthly' ? 'Monthly' : 'Annual';

    String pitchText;
    if (profile.isPremium) {
      final currentTier = profile.pendingSubscriptionTier?.toLowerCase() ?? '';
      if (currentTier == plan) {
        pitchText =
            "Ready to extend your *$planLabel Plan*? Awesome! 🥳\n\n$gatewayName requires an email address for your secure checkout. Please reply with your best email address so I can generate your link.\n\n(Don't worry, you won't be charged just by typing your email!)";
      } else {
        pitchText =
            "Upgrading to the *Annual Plan*? Fantastic choice! 🎉\n\n$gatewayName requires an email address for your secure checkout. Please reply with your best email address so I can generate your link.\n\n(Don't worry, you won't be charged just by typing your email!)";
      }
    } else {
      pitchText =
          "Amazing choice! 🎉 Let's get you set up on the *$planLabel Plan*.\n\n$gatewayName requires an email address to securely process your receipt. Please reply with your best email address so I can generate your checkout link.\n\n(Don't worry, you won't be charged just by typing your email!)";
      if (!isPaystack) {
        pitchText +=
            "\n\n(Note: Your exact price in £ or € or \$ will be calculated automatically at checkout).";
      }
    }

    await whatsappService.sendMessage(from, pitchText);
  }

  // ==========================================================
  // EMAIL & CHECKOUT
  // ==========================================================

  /// Handles email input for checkout generation.
  Future<void> handleEmailForUpgrade(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    final email = text.trim();

    if (!email.contains('@')) {
      await whatsappService.sendMessage(from,
          "That doesn't look like a valid email. Please reply with a valid email address, or type *Cancel* to exit.");
      return;
    }

    await whatsappService.sendMessage(
        from, "Generating your secure payment link... ⏳");

    try {
      final plan = profile.pendingSubscriptionTier ?? 'monthly';
      final isPaystack = CountryUtils.isPaystackRegion(from);

      String checkoutUrl;
      String referenceOrLocalId;

      if (isPaystack) {
        final amount = plan == 'monthly'
            ? Pricing.monthlyNgn.toDouble()
            : Pricing.annualNgn.toDouble();

        final result = await paystackService.initializeTransaction(
            email: email, amount: amount, currency: 'NGN');
        checkoutUrl = result['authorization_url']!;
        referenceOrLocalId = result['reference']!;
      } else {
        // Lemon Squeezy
        final variantId = plan == 'monthly'
            ? Platform.environment['LS_VARIANT_MONTHLY'] ?? ''
            : Platform.environment['LS_VARIANT_ANNUAL'] ?? '';

        checkoutUrl = await lemonSqueezyService.createCheckout(
          email: email,
          variantId: variantId,
          phoneNumber: from,
          planName: plan == 'monthly' ? 'Monthly' : 'Annual',
        );
        referenceOrLocalId = 'ls_${DateTime.now().millisecondsSinceEpoch}';
      }

      // Save the reference and email
      await firestoreService.updateProfileData(from, {
        'email': email,
        'pendingPaymentReference': referenceOrLocalId,
        'currentAction': UserAction.idle.name,
      });

      await whatsappService.sendInteractiveButtons(
        from,
        "Click the link below to securely complete your upgrade to Premium! 🚀\n\n$checkoutUrl\n\nOnce paid, you will be automatically upgraded. If it doesn't happen instantly, tap the button below.",
        [
          {'id': ButtonIds.verifyPayment, 'title': '✅ Verify Payment'},
        ],
      );
    } catch (e) {
      print("Payment initialization error: $e");
      await whatsappService.sendMessage(from,
          "Sorry, there was an issue generating your payment link. Please try again later.");
      await firestoreService.updateAction(from, UserAction.idle);
    }
  }

  // ==========================================================
  // SUBSCRIPTION STATUS
  // ==========================================================

  /// Shows the current subscription status.
  Future<void> showSubscriptionStatus(
      String from, BusinessProfile profile) async {
    if (profile.role != UserRole.admin) {
      await whatsappService.sendMessage(
          from, "Only Admins can view this info.");
      return;
    }

    if (profile.isPremium) {
      final tierName = profile.pendingSubscriptionTier ?? "Premium";
      if (profile.premiumExpiresAt != null) {
        final expiry = profile.premiumExpiresAt!;
        final daysLeft = expiry.difference(DateTime.now()).inDays;
        final dateStr = "${expiry.day}/${expiry.month}/${expiry.year}";

        await whatsappService.sendMessage(from,
            "💎 *Subscription Active*\n\nYou are currently on the *$tierName* tier.\nYour access expires on *$dateStr* ($daysLeft days remaining).\n\nIf you'd like to extend your time, type *Upgrade*.");
      } else {
        await whatsappService.sendMessage(from,
            "💎 *Subscription Active*\n\nYou are currently on the *$tierName* tier, however your expiration date could not be read.");
      }
    } else {
      await whatsappService.sendMessage(from,
          "You are currently on the *Free Tier*. Upgrade today to unlock pro layouts and remove limits!");
    }
  }

  // ==========================================================
  // PAYMENT VERIFICATION
  // ==========================================================

  /// Handles manual payment verification request.
  Future<void> handleVerifyPayment(String from, BusinessProfile profile) async {
    if (profile.pendingPaymentReference == null ||
        profile.pendingPaymentReference!.isEmpty) {
      await whatsappService.sendMessage(
        from,
        "You don't have any pending payments. Type *Upgrade* to start one!",
      );
      return;
    }

    // International payments (Lemon Squeezy) are webhook-verified
    if (profile.pendingPaymentReference!.startsWith('ls_')) {
      await whatsappService.sendMessage(
        from,
        "🌍 International payments are verified automatically by our system.\n\nIf you just completed your checkout, please wait a minute or two for your Premium status to activate. Contact support if you need further assistance.",
      );
      return;
    }

    await whatsappService.sendMessage(
        from, "Checking your payment status... ⏳");

    try {
      final verifyData = await paystackService
          .verifyTransaction(profile.pendingPaymentReference!);
      final status = verifyData['status'];
      final amountInKobo = verifyData['amount'] as num;

      if (status == 'success' &&
          amountInKobo >= Pricing.minimumValidPaymentKobo) {
        // Determine plan from amount
        final daysToAdd = amountInKobo >= Pricing.annualNgnKobo ? 365 : 30;

        await firestoreService.updateProfileData(from, {
          'isPremium': true,
          'premiumExpiresAt':
              DateTime.now().add(Duration(days: daysToAdd)).toIso8601String(),
          'pendingPaymentReference': '',
          'receiptCount': 0, // Reset count on upgrade
        });

        await whatsappService.sendMessage(
          from,
          "🎉 *Payment Successful!* 🎉\n\nYou are now a Premium user! Enjoy advanced layouts and  Logo on receipts!",
        );
      } else if (status == 'success') {
        final amountNgn = amountInKobo / 100;
        await whatsappService.sendMessage(
          from,
          "⚠️ *Partial Payment Received* ⚠️\n\nWe received a payment of ₦$amountNgn, but Premium upgrade requires ₦${Pricing.monthlyNgn}. Please contact support to resolve this.",
        );
      } else {
        await whatsappService.sendMessage(
          from,
          "Your payment is still pending or was not successful.\n\nIf you just paid, please wait a minute and try again. If you haven't paid yet, you can still use the payment link provided earlier.",
        );
      }
    } catch (e) {
      print("Manual verify error: $e");
      await whatsappService.sendMessage(
        from,
        "Sorry, I couldn't verify your payment right now. Please try again later.",
      );
    }
  }

  // ==========================================================
  // FREEMIUM CHECKS
  // ==========================================================

  /// Checks if user has exceeded their monthly free limit.
  /// Returns true if the user can proceed, false if they hit the limit.
  Future<bool> checkFreemiumLimit(String from, BusinessProfile profile) async {
    if (profile.isPremium) return true;

    final now = DateTime.now();
    final currentMonthStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}";
    int currentCount = profile.receiptCount;

    if (profile.lastReceiptMonth != currentMonthStr) {
      currentCount = 0;
    }

    if (currentCount >= 5) {
      await firestoreService.updateAction(from, UserAction.idle);

      final isPaystack = CountryUtils.isPaystackRegion(from);
      final monthlyDesc = isPaystack
          ? 'Unlimited (₦${Pricing.monthlyNgn}/mo)'
          : r'Flexible ($' '${Pricing.monthlyUsd}/mo)';
      final annualDesc = isPaystack
          ? 'Save ₦7,000! (₦${Pricing.annualNgn}/yr)'
          : r'Save $16! ($' '${Pricing.annualUsd}/yr)';

      await whatsappService.sendInteractiveList(
        from,
        "🚫 *Monthly Limit Reached*\n\nYou have generated 5 free receipts/invoices this month. Tap below to unlock unlimited generations!",
        "View Plans",
        "Select Plan",
        [
          {
            'id': ButtonIds.monthly,
            'title': 'Monthly Plan',
            'description': monthlyDesc
          },
          {
            'id': ButtonIds.yearly,
            'title': 'Annual Plan',
            'description': annualDesc
          },
        ],
      );
      return false;
    }

    return true;
  }

  /// Handles post-receipt freemium warnings and count updates.
  Future<void> handleFreemiumPostReceipt(
    String from,
    BusinessProfile profile,
  ) async {
    if (profile.isPremium) return;

    final now = DateTime.now();
    final currentMonthStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}";
    final int newCount = (profile.lastReceiptMonth == currentMonthStr)
        ? profile.receiptCount + 1
        : 1;

    await firestoreService.updateProfileData(from, {
      'receiptCount': newCount,
      'lastReceiptMonth': currentMonthStr,
    });

    // Send appropriate warnings based on count
    await Future<void>.delayed(const Duration(seconds: 1));

    if (newCount == 3) {
      await whatsappService.sendMessage(from,
          "⚠️ *Notice:* You have 2 free generation left this month. Type *Upgrade* to unlock unlimited access.");
    } else if (newCount >= 5) {
      final isPaystack = CountryUtils.isPaystackRegion(from);
      await whatsappService.sendInteractiveList(
        from,
        "🎉 You just used your last free receipt for this month!\n\nTo continue generating unlimited professional receipts, tap below to unlock Premium.",
        "View Plans",
        "Select Plan",
        [
          {
            'id': ButtonIds.monthly,
            'title': 'Monthly Plan',
            'description': isPaystack
                ? 'Unlimited (₦${Pricing.monthlyNgn}/mo)'
                : r'Unlimited ($' '${Pricing.monthlyUsd}/mo)'
          },
          {
            'id': ButtonIds.yearly,
            'title': 'Annual Plan',
            'description': isPaystack
                ? 'Save ₦7,000! (₦${Pricing.annualNgn}/yr)'
                : r'Save $16! ($' '${Pricing.annualUsd}/yr)'
          },
        ],
      );
    } else if (!profile.hasSeenPremiumTip) {
      await whatsappService.sendMessage(from,
          "💡 **Tip:** Want your logo on every receipt? Reply with *Upgrade* to unlock custom branding and premium layouts!");

      await firestoreService.updateProfileData(from, {
        'hasSeenPremiumTip': true,
      });
    }
  }

  // ==========================================================
  // SUBSCRIPTION RECEIPT GENERATION
  // ==========================================================

  /// Generates and sends a proof of payment receipt for a subscription.
  Future<void> generateAndSendSubscriptionReceipt(
    String phoneNumber,
    BusinessProfile profile,
    String planName,
    num amountPaid,
    String currencyCode,
  ) async {
    try {
      print('Generating Subscription Receipt for $phoneNumber...');

      // Create a synthetic Transaction
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

      final resolvedCurrencySymbol = _getCurrencySymbol(currencyCode);

      final botOrg = Organization(
        id: 'bot_org',
        businessName: 'ReceiptBot Inc.',
        businessAddress: 'Global Digital Service',
        displayPhoneNumber: '+2348021146844',
        logoUrl:
            'https://firebasestorage.googleapis.com/v0/b/invoicemaker-b3876.appspot.com/o/receipts%2Fbot_logo.png?alt=media',
        inviteCode: '',
        currencyCode: currencyCode,
        currencySymbol: resolvedCurrencySymbol,
      );

      // Generate PDF (Signature Layout, Classic Theme)
      final pdfBytes = await pdfService.generateReceipt(
        profile,
        transaction,
        themeIndex: 0,
        layoutIndex: 1,
        org: botOrg,
      );

      // Upload to Firebase Storage
      final fileName =
          'proof_of_payment_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfUrl = await firestoreService.uploadFile(
        'receipts/$phoneNumber/$fileName',
        pdfBytes,
        'application/pdf',
      );

      // Send via WhatsApp
      await whatsappService.sendDocument(phoneNumber, pdfUrl, fileName);
      print('Subscription Receipt sent successfully to $phoneNumber');
    } catch (e) {
      print('Error generating subscription receipt for $phoneNumber: $e');
    }
  }

  String _getCurrencySymbol(String code) {
    switch (code) {
      case 'NGN':
        return '₦';
      case 'GBP':
        return '£';
      case 'EUR':
        return '€';
      default:
        return r'$';
    }
  }
}
