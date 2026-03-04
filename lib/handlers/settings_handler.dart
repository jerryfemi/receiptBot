import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/gemini_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/constants.dart';

/// URLs for layout preview images.
abstract class LayoutUrls {
  static const String corporate =
      'https://firebasestorage.googleapis.com/v0/b/invoicemaker-b3876.firebasestorage.app/o/layouts%2Fstandard.png?alt=media';
  static const String signature =
      'https://firebasestorage.googleapis.com/v0/b/invoicemaker-b3876.firebasestorage.app/o/layouts%2Fsignature.png?alt=media';
  static const String simple =
      'https://firebasestorage.googleapis.com/v0/b/invoicemaker-b3876.firebasestorage.app/o/layouts%2Fsimple.png?alt=media';
  static const String legacy =
      'https://firebasestorage.googleapis.com/v0/b/invoicemaker-b3876.firebasestorage.app/o/layouts%2Fclassic.png?alt=media';
}

/// Handles profile settings, team management, and customization flows.
class SettingsHandler {
  final FirestoreService firestoreService;
  final WhatsAppService whatsappService;
  final GeminiService geminiService;

  SettingsHandler({
    required this.firestoreService,
    required this.whatsappService,
    required this.geminiService,
  });

  // ==========================================================
  // HELPER: Updates profile and organization data (for admins)
  // ==========================================================

  Future<void> updateProfileAndOrg(
    String from,
    BusinessProfile profile,
    Map<String, dynamic> data,
  ) async {
    await firestoreService.updateProfileData(from, data);
    if (profile.role == UserRole.admin && profile.orgId != null) {
      await firestoreService.updateOrganizationData(profile.orgId!, data);
    }
  }

  // ==========================================================
  // SETTINGS MENU
  // ==========================================================

  /// Shows the main settings menu.
  Future<void> showSettingsMenu(String from, bool isPremium) async {
    await whatsappService.sendInteractiveList(
      from,
      '⚙️ *Settings Menu*\nWhat would you like to configure? 👇',
      'View Options',
      'Settings',
      MenuOptions.settingsMenu(isPremium: isPremium),
    );
  }

  /// Shows the edit profile menu.
  Future<void> showEditProfileMenu(String from) async {
    await firestoreService.updateAction(from, UserAction.editProfileMenu);
    await whatsappService.sendInteractiveList(
      from,
      'What would you like to update? 👇',
      'View Options',
      'Edit Profile',
      MenuOptions.editProfile,
    );
  }

  /// Shows the "loop back" edit profile menu after an action completes.
  Future<void> showEditProfileMenuContinue(String from) async {
    await firestoreService.updateAction(from, UserAction.editProfileMenu);
    await whatsappService.sendInteractiveList(
      from,
      'What else would you like to update? 👇',
      'View Options',
      'Edit Profile',
      MenuOptions.editProfileShort,
    );
  }

  // ==========================================================
  // EDIT PROFILE MENU HANDLER
  // ==========================================================

  /// Processes selection in the edit profile menu.
  Future<void> handleEditProfileMenuSelection(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    if (profile.role != UserRole.admin) {
      await whatsappService.sendMessage(
          from, "Only Admins can edit the profile.");
      await firestoreService.updateAction(from, UserAction.idle);
      return;
    }

    final lower = text.toLowerCase().trim();

    // Business Name
    if (lower == '1' ||
        lower == ButtonIds.editName ||
        lower == 'business name') {
      await firestoreService.updateAction(from, UserAction.editName);
      await whatsappService.sendMessage(
        from,
        'Okay, send me the **New Business Name**.\n\nType *Back* to return or *Cancel* to exit.',
      );
      return;
    }

    // Phone Number
    if (lower == '2' ||
        lower == ButtonIds.editPhone ||
        lower == 'phone number') {
      await firestoreService.updateAction(from, UserAction.editPhone);
      await whatsappService.sendMessage(
        from,
        'Okay, send me the **New Phone Number**.\n\nType *Back* to return or *Cancel* to exit.',
      );
      return;
    }

    // Bank Details
    if (lower == '3' ||
        lower == ButtonIds.editBank ||
        lower == 'bank details') {
      await firestoreService.updateAction(from, UserAction.editBankDetails);
      await whatsappService.sendMessage(
        from,
        'Okay, send me your **Bank Details**:\n\nBank Name, Account Number, Account Name\n\nType *Back* to return or *Cancel* to exit.',
      );
      return;
    }

    // Theme
    if (lower == '4' || lower == ButtonIds.editTheme || lower == 'theme') {
      await firestoreService.updateAction(from, UserAction.selectTheme);
      await whatsappService.sendInteractiveButtons(
        from,
        "Select a new *Theme (Color)*:",
        MenuOptions.themes,
      );
      return;
    }

    // Layout
    if (lower == '5' || lower == ButtonIds.editLayout || lower == 'layout') {
      if (!profile.isPremium) {
        await whatsappService.sendInteractiveButtons(
          from,
          "💎 *Premium Feature*\n\nCustom layouts (Modern, Minimal, Signature) are only available for Premium users!",
          [
            {'id': ButtonIds.upgrade, 'title': '⭐ Upgrade'},
            {'id': ButtonIds.back, 'title': '⬅ Back'},
          ],
        );
        return;
      }

      await _showLayoutSelection(from);
      return;
    }

    // Address
    if (lower == '6' || lower == ButtonIds.editAddress || lower == 'address') {
      await firestoreService.updateAction(from, UserAction.editAddress);
      await whatsappService.sendMessage(
        from,
        'Okay, send me the *New Business Address*.\n\nType *Back* to return or *Cancel* to exit.',
      );
      return;
    }

    // Currency
    if (lower == '7' ||
        lower == ButtonIds.changeCurrency ||
        lower == 'currency') {
      await _showCurrencySelection(from);
      return;
    }

    // Logo (sometimes accessed directly)
    if (lower == ButtonIds.editLogo ||
        lower == 'logo' ||
        lower == 'upload logo') {
      await firestoreService.updateAction(from, UserAction.editLogo);
      await whatsappService.sendMessage(from,
          'Okay, send me the *New Logo Image*.\n\n⚠️ *If your logo has a transparent background, upload it as a Document so WhatsApp keeps it transparent!*\n\nType *Back* to return or *Cancel* to exit.');
      return;
    }

    // Invalid selection
    await whatsappService.sendMessage(from,
        'Please select an option from the list or reply with a number (1-8).');
  }

  // ==========================================================
  // INDIVIDUAL FIELD HANDLERS
  // ==========================================================

  /// Handles business name update.
  Future<void> handleEditName(
    String from,
    String text,
    String type,
    BusinessProfile profile,
  ) async {
    if (type != 'text') {
      await whatsappService.sendMessage(from, 'Please send text for the name.');
      return;
    }

    try {
      await updateProfileAndOrg(from, profile, {'businessName': text});
      await whatsappService.sendMessage(
          from, "Business Name updated to '$text'! ✅");
    } catch (e) {
      print('Error updating business name: $e');
      await whatsappService.sendMessage(
          from, 'Failed to update business name. Please try again.');
    }

    await showEditProfileMenuContinue(from);
  }

  /// Handles phone number update.
  Future<void> handleEditPhone(
    String from,
    String text,
    String type,
    BusinessProfile profile,
  ) async {
    if (type != 'text') {
      await whatsappService.sendMessage(
          from, 'Please send text for the phone number.');
      return;
    }

    try {
      await updateProfileAndOrg(from, profile, {'displayPhoneNumber': text});
      await whatsappService.sendMessage(
          from, "Phone Number updated to '$text'! ✅");
    } catch (e) {
      print('Error updating phone number: $e');
      await whatsappService.sendMessage(
          from, 'Failed to update phone number. Please try again.');
    }

    await showEditProfileMenuContinue(from);
  }

  /// Handles address update.
  Future<void> handleEditAddress(
    String from,
    String text,
    String type,
    BusinessProfile profile,
  ) async {
    if (type != 'text') {
      await whatsappService.sendMessage(
          from, 'Please send text for the address.');
      return;
    }

    try {
      await updateProfileAndOrg(from, profile, {'businessAddress': text});
      await whatsappService.sendMessage(from, "Address updated to '$text'! ✅");
    } catch (e) {
      print('Error updating address: $e');
      await whatsappService.sendMessage(
          from, 'Failed to update address. Please try again.');
    }

    await showEditProfileMenuContinue(from);
  }

  /// Handles bank details update using Gemini parsing.
  Future<void> handleEditBankDetails(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    try {
      final transaction = await geminiService.parseTransaction(text);
      if (transaction.bankName != null) {
        await updateProfileAndOrg(from, profile, {
          'bankName': transaction.bankName,
          'accountNumber': transaction.accountNumber,
          'accountName': transaction.accountName,
        });
        await whatsappService.sendMessage(from, 'Bank Details Updated! ✅');
      } else {
        await whatsappService.sendMessage(
          from,
          "I couldn't find bank details. Please try again (e.g. GTBank, 0123456789, Name).",
        );
      }

      await showEditProfileMenuContinue(from);
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

  /// Handles logo upload.
  Future<void> handleEditLogo(
    String from,
    String type,
    Map<String, dynamic> messageData,
    BusinessProfile profile,
  ) async {
    if (type != 'image' && type != 'document') {
      await whatsappService.sendMessage(
          from, 'Please send an image or document.');
      return;
    }

    try {
      final mediaId = type == 'image'
          ? messageData['image']['id'] as String
          : messageData['document']['id'] as String;

      final tempUrl = await whatsappService.getMediaUrl(mediaId);
      final bytes = await whatsappService.downloadFileBytes(tempUrl);

      final publicUrl = await firestoreService.uploadFile(
        'logos/$from.jpg',
        bytes,
        'image/jpeg',
      );

      await whatsappService.sendMessage(from, 'Saving Logo...... ');
      await updateProfileAndOrg(from, profile, {'logoUrl': publicUrl});
      await whatsappService.sendMessage(from, 'Logo updated successfully! 🖼️');
    } catch (e) {
      print('Error updating logo: $e');
      await whatsappService.sendMessage(
          from, 'Failed to save logo. Please try again.');
    }

    await showEditProfileMenuContinue(from);
  }

  // ==========================================================
  // CURRENCY SELECTION
  // ==========================================================

  Future<void> _showCurrencySelection(String from) async {
    await firestoreService.updateAction(from, UserAction.selectCurrency);

    const currencies = CountryUtils.supportedCurrencies;
    final listOptions = currencies
        .asMap()
        .entries
        .map((e) => {
              'id': (e.key + 1).toString(),
              'title': '${e.value['code']} (${e.value['symbol']})',
              'description': e.value['name'].toString(),
            })
        .toList();

    await whatsappService.sendInteractiveList(
      from,
      'Select your **Currency**:',
      'Select Currency',
      'Currencies',
      listOptions,
    );
  }

  /// Handles currency selection.
  Future<void> handleCurrencySelection(
    String from,
    String text,
    BusinessProfile profile,
  ) async {
    final index = int.tryParse(text) ?? 0;
    const currencies = CountryUtils.supportedCurrencies;

    if (index > 0 && index <= currencies.length) {
      final selected = currencies[index - 1];
      try {
        await updateProfileAndOrg(from, profile, {
          'currencyCode': selected['code'],
          'currencySymbol': selected['symbol'],
        });

        await whatsappService.sendMessage(from,
            'Currency updated to ${selected['code']} (${selected['symbol']})! ✅');

        await showEditProfileMenuContinue(from);
      } catch (e) {
        print('Error updating currency: $e');
        await whatsappService.sendMessage(
            from, 'Failed to update currency. Please try again later.');
        await firestoreService.updateAction(from, UserAction.idle);
      }
    } else {
      await whatsappService.sendMessage(
          from, 'Please reply with a valid number from the list.');
    }
  }

  // ==========================================================
  // THEME SELECTION
  // ==========================================================

  /// Handles theme selection (for both profile edit and receipt generation).
  /// Returns the selected theme index, or null if invalid selection.
  int? parseThemeSelection(String text) {
    final lower = text.toLowerCase().trim();
    if (lower == ButtonIds.themeClassic ||
        lower == '1' ||
        lower == 'classic' ||
        lower == 'b&w (classic)') {
      return 0;
    } else if (lower == ButtonIds.themeBeige ||
        lower == '2' ||
        lower == 'beige') {
      return 1;
    }
    return null;
  }

  /// Handles theme selection for profile settings (no pending transaction).
  Future<void> handleThemeSelectionForProfile(
    String from,
    int themeIndex,
    BusinessProfile profile,
  ) async {
    await updateProfileAndOrg(from, profile, {'themeIndex': themeIndex});
    await whatsappService.sendMessage(from, 'Default theme updated! ✅');
    await showEditProfileMenuContinue(from);
  }

  // ==========================================================
  // LAYOUT SELECTION
  // ==========================================================

  Future<void> _showLayoutSelection(String from) async {
    await firestoreService.updateAction(from, UserAction.selectLayout);
    await whatsappService.sendMessage(
        from, "Please select a *Layout Structure*.");

    // Send layout previews with selection buttons
    await whatsappService.sendInteractiveMedia(
        from, LayoutUrls.corporate, 'image',
        bodyText: '1️⃣ Corporate (Premium & High-Impact) ⭐ Recommended',
        buttons: [
          {'id': ButtonIds.layoutCorporate, 'title': 'Select Corporate'}
        ]);

    await whatsappService.sendInteractiveMedia(
        from, LayoutUrls.signature, 'image',
        bodyText: '2️⃣ Signature (Elegant script font)',
        buttons: [
          {'id': ButtonIds.layoutSignature, 'title': 'Select Signature'}
        ]);

    await whatsappService.sendInteractiveMedia(from, LayoutUrls.simple, 'image',
        bodyText: '3️⃣ Simple (Strict grid structure)',
        buttons: [
          {'id': ButtonIds.layoutSimple, 'title': 'Select Simple'}
        ]);

    await whatsappService.sendInteractiveMedia(from, LayoutUrls.legacy, 'image',
        bodyText: '4️⃣ Legacy (default plain layout)',
        buttons: [
          {'id': ButtonIds.layoutLegacy, 'title': 'Select Legacy'}
        ]);
  }

  /// Parses layout selection text. Returns layout index or null.
  int? parseLayoutSelection(String text) {
    final lower = text.toLowerCase().trim();
    if (lower == ButtonIds.layoutLegacy ||
        lower == '1' ||
        lower == 'legacy' ||
        lower == 'default' ||
        lower == 'classic') {
      return 0;
    } else if (lower == ButtonIds.layoutSignature ||
        lower == '2' ||
        lower == 'signature') {
      return 1;
    } else if (lower == ButtonIds.layoutSimple ||
        lower == '3' ||
        lower == 'simple') {
      return 2;
    } else if (lower == ButtonIds.layoutCorporate ||
        lower == '4' ||
        lower == 'corporate' ||
        lower == 'standard') {
      return 3;
    }
    return null;
  }

  /// Handles layout selection for profile settings (no pending transaction).
  Future<void> handleLayoutSelectionForProfile(
    String from,
    int layoutIndex,
    BusinessProfile profile,
  ) async {
    await updateProfileAndOrg(from, profile, {'layoutIndex': layoutIndex});
    await whatsappService.sendMessage(from, 'Default layout updated! ✅');
    await showEditProfileMenuContinue(from);
  }

  // ==========================================================
  // TEAM MANAGEMENT
  // ==========================================================

  /// Shows team management menu with invite code and member list.
  Future<void> showTeamManagement(String from, BusinessProfile profile) async {
    if (profile.role != UserRole.admin) {
      await whatsappService.sendMessage(
          from, 'Only Admins can manage team members.');
      return;
    }

    if (profile.orgId == null) {
      await whatsappService.sendMessage(
        from,
        'You are not currently part of an organization. Please recreate your profile to get an invite code.',
      );
      return;
    }

    final teamMembers = await firestoreService.getTeamMembers(profile.orgId!);
    final agents = teamMembers.where((m) => m.phoneNumber != from).toList();

    String message = '👥 *Team Management*\n\n';

    final org = await firestoreService.getOrganization(profile.orgId!);
    message += 'Your Team Invite Code is:\n*${org?.inviteCode ?? "N/A"}*\n\n';

    if (agents.isEmpty) {
      message +=
          'You currently have no other team members.\nShare the code above for them to join!';
      await whatsappService.sendMessage(from, message);
    } else {
      message += 'Select a team member to remove:';

      final listOptions = agents.map((agent) {
        return {
          'id': '${ButtonIds.removeTeamMemberPrefix}${agent.phoneNumber}',
          'title': agent.businessName ?? agent.phoneNumber,
          'description': 'Remove this member'
        };
      }).toList();

      await firestoreService.updateAction(from, UserAction.removeTeamMember);
      await whatsappService.sendInteractiveList(
        from,
        message,
        'Select Member',
        'Team Members',
        listOptions,
      );
    }
  }

  /// Handles team member removal - shows confirmation first.
  Future<void> handleRemoveTeamMember(
    String from,
    String text,
  ) async {
    final lower = text.toLowerCase().trim();

    // Handle cancel
    if (lower == 'cancel' || lower == ButtonIds.cancel) {
      await firestoreService.updateAction(from, UserAction.idle);
      await whatsappService.sendMessage(from, 'Action cancelled.');
      return;
    }

    // Validate selection format
    if (!text.startsWith(ButtonIds.removeTeamMemberPrefix)) {
      await whatsappService.sendMessage(
          from, 'Please select a team member from the list or type *Cancel*.');
      return;
    }

    // Extract target phone and show confirmation
    final targetPhone = text.replaceFirst(ButtonIds.removeTeamMemberPrefix, '');

    // Get member name for confirmation message
    String memberName = targetPhone;
    try {
      final targetProfile = await firestoreService.getProfile(targetPhone);
      if (targetProfile?.businessName != null) {
        memberName = targetProfile!.businessName!;
      }
    } catch (_) {}

    // Move to confirmation state and show confirmation buttons
    await firestoreService.updateAction(
        from, UserAction.confirmRemoveTeamMember);
    await whatsappService.sendInteractiveButtons(
      from,
      '⚠️ *Are you sure you want to remove $memberName?*\n\nThis action cannot be undone. The member will lose access to your organization immediately.',
      [
        {
          'id': '${ButtonIds.confirmRemovePrefix}$targetPhone',
          'title': '✅ Yes, Remove'
        },
        {'id': ButtonIds.cancel, 'title': '❌ Cancel'},
      ],
    );
  }

  /// Handles the confirmation response for team member removal.
  Future<void> handleConfirmRemoveTeamMember(
    String from,
    String text,
  ) async {
    final lower = text.toLowerCase().trim();

    // Handle cancel
    if (lower == 'cancel' || lower == ButtonIds.cancel || lower == 'no') {
      await firestoreService.updateAction(from, UserAction.idle);
      await whatsappService.sendMessage(
          from, 'Removal cancelled. Team member was not removed.');
      return;
    }

    // Check for confirmation
    if (!text.startsWith(ButtonIds.confirmRemovePrefix)) {
      await whatsappService.sendMessage(
          from, 'Please tap *Yes, Remove* or *Cancel*.');
      return;
    }

    final targetPhone = text.replaceFirst(ButtonIds.confirmRemovePrefix, '');
    await whatsappService.sendMessage(from, 'Removing team member... ⏳');

    try {
      await firestoreService.removeTeamMember(targetPhone);
      await whatsappService.sendMessage(
          from, 'Team member removed successfully. ✅');

      // Notify the removed user (non-blocking)
      try {
        await whatsappService.sendMessage(targetPhone,
            'ℹ️ You have been removed from the organization by the Admin. Your account has been reset.');
      } catch (_) {}
    } catch (e) {
      print('Error removing team member: $e');
      await whatsappService.sendMessage(
          from, '⚠️ Failed to remove team member. Please try again.');
    }

    await firestoreService.updateAction(from, UserAction.idle);
  }
}
