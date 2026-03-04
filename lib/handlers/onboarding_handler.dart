import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/constants.dart';

/// Handles user onboarding flows (new user, join team, setup profile).
class OnboardingHandler {
  final FirestoreService firestoreService;
  final WhatsAppService whatsappService;

  OnboardingHandler({
    required this.firestoreService,
    required this.whatsappService,
  });

  /// Handles message for new users (not yet onboarded).
  Future<void> handleNewUser(String from) async {
    await whatsappService.sendInteractiveButtons(
      from,
      "Welcome! \n\nI can help you generate professional Receipts & Invoices internally.\n\nAre you here to:",
      [
        {'id': ButtonIds.createProfile, 'title': '🏢 Create Profile'},
        {'id': ButtonIds.joinTeam, 'title': '🤝 Join Team'},
      ],
    );
    await firestoreService.updateOnboardingStep(
        from, OnboardingStatus.awaiting_setup_choice);
  }

  /// Handles the user's choice between creating profile vs joining team.
  Future<void> handleSetupChoice(String from, String text) async {
    final choice = text.trim();

    if (choice == ButtonIds.createProfile) {
      await firestoreService.updateOnboardingStep(
        from,
        OnboardingStatus.awaiting_address,
      );
      await whatsappService.sendMessage(
          from, "Let's start! What is your *Business Name*?");
    } else if (choice == ButtonIds.joinTeam) {
      await firestoreService.updateOnboardingStep(
        from,
        OnboardingStatus.awaiting_invite_code,
      );
      await whatsappService.sendMessage(from,
          "Great! Please reply with the 6-character Invite Code your admin gave you.\n\nType *Cancel* to exit.");
    } else {
      // Invalid selection - show buttons again
      await whatsappService.sendInteractiveButtons(
        from,
        "Please make a selection to proceed:",
        [
          {'id': ButtonIds.createProfile, 'title': '🏢 Create Profile'},
          {'id': ButtonIds.joinTeam, 'title': '🤝 Join Team'},
        ],
      );
    }
  }

  /// Handles invite code submission for joining a team.
  Future<void> handleInviteCode(String from, String text) async {
    final code = text.trim().toUpperCase();

    // Handle cancel command
    if (code.toLowerCase() == 'cancel') {
      await firestoreService.updateOnboardingStep(
          from, OnboardingStatus.new_user);
      await whatsappService.sendMessage(from, 'Action cancelled.');
      await handleNewUser(from);
      return;
    }

    await whatsappService.sendMessage(from, "Checking code... 🔎");

    final orgId = await firestoreService.findOrganizationByInviteCode(code);

    if (orgId != null) {
      final org = await firestoreService.getOrganization(orgId);
      await firestoreService.updateProfileData(from, {
        'orgId': orgId,
        'role': UserRole.agent.name,
        'status': OnboardingStatus.active.name,
      });

      await whatsappService.sendMessage(from,
          "Success! 🎉 You are now linked to **${org?.businessName ?? 'your team'}** as a Sales Agent.\n\nYou can now send me receipt details and I will generate them using the company's official template.");

      // Notify admin
      await _notifyAdminOfNewMember(orgId, from);
    } else {
      await whatsappService.sendMessage(from,
          "Oops, that code is invalid. Please try again or ask your admin for the correct code, or type 'cancel' to restart.");
    }
  }

  /// Handles business name input during profile creation.
  Future<void> handleBusinessName(String from, String text) async {
    // Handle cancel command
    if (text.trim().toLowerCase() == 'cancel') {
      await firestoreService.updateOnboardingStep(
          from, OnboardingStatus.new_user);
      await whatsappService.sendMessage(from, 'Action cancelled.');
      await handleNewUser(from);
      return;
    }

    final businessName = text.trim();
    final newOrgId = await firestoreService.createOrganization(businessName);

    await firestoreService.updateProfileData(from, {
      'orgId': newOrgId,
      'role': UserRole.admin.name,
    });

    await firestoreService.updateOnboardingStep(
      from,
      OnboardingStatus.awaiting_phone,
      data: {'businessName': businessName},
    );

    await whatsappService.sendMessage(
      from,
      'Great! Now, what is your *Business Address*?\n\nType *Cancel* to exit.',
    );
  }

  /// Handles business address input during profile creation.
  Future<void> handleBusinessAddress(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    // Handle cancel command
    if (text.trim().toLowerCase() == 'cancel') {
      await firestoreService.updateOnboardingStep(
          from, OnboardingStatus.new_user);
      await whatsappService.sendMessage(from, 'Action cancelled.');
      await handleNewUser(from);
      return;
    }

    final address = text.trim();

    await firestoreService.updateOnboardingStep(
      from,
      OnboardingStatus.active,
      data: {
        'businessAddress': address,
        'themeIndex': 0,   // Default to Classic theme
        'layoutIndex': 3,  // Default to Corporate layout
      },
    );

    if (profile.orgId != null) {
      await firestoreService.updateOrganizationData(
        profile.orgId!,
        {'businessAddress': address},
      );
    }

    // Build completion buttons based on role
    final List<Map<String, String>> buttons = [
      {'id': ButtonIds.createReceipt, 'title': '🧾 Receipt'},
      {'id': ButtonIds.createInvoice, 'title': '📄 Invoice'},
    ];

    if (profile.role == UserRole.admin) {
      buttons.add({'id': ButtonIds.settings, 'title': '⚙️ Settings'});
    } else {
      buttons.add({'id': ButtonIds.help, 'title': '❓ Help'});
    }

    await whatsappService.sendInteractiveButtons(
      from,
      'Setup Complete! 🎉\n\nYou can now create receipts and invoices.\n\n💡 *Pro Tip:* You can tap the buttons below, or simply type *"Create Receipt"*, *"Menu"*, or *"Help"* at any time!\n\n_What would you like to do first?_',
      buttons,
    );
  }

  /// Notifies the organization admin when a new team member joins.
  Future<void> _notifyAdminOfNewMember(
      String orgId, String newMemberPhone) async {
    try {
      final teamMembers = await firestoreService.getTeamMembers(orgId);
      final admin = teamMembers.firstWhere(
        (member) => member.role == UserRole.admin,
        orElse: () => teamMembers.first,
      );

      await whatsappService.sendMessage(
        admin.phoneNumber,
        "✅ *New Team Member!*\nA new agent ($newMemberPhone) has successfully joined your organization and is now ready to generate receipts and invoices.",
      );
    } catch (e) {
      print('Failed to notify admin of new member: $e');
      // Non-critical - don't fail the flow
    }
  }
}
