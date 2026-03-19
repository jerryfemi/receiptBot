/// Centralized button and action ID constants.
/// All interactive button/list IDs should be defined here to ensure consistency.
abstract class ButtonIds {
  // === MAIN ACTIONS ===
  static const String createReceipt = 'btn_create_receipt';
  static const String createInvoice = 'btn_create_invoice';
  static const String settings = 'btn_settings';
  static const String help = 'help';
  static const String cancel = 'btn_cancel';
  static const String back = 'btn_back';

  // === ONBOARDING ===
  static const String createProfile = '1';
  static const String joinTeam = '2';

  // === PROFILE EDITING ===
  static const String editProfile = 'btn_edit_profile';
  static const String editName = 'btn_edit_name';
  static const String editPhone = 'btn_edit_phone';
  static const String editBank = 'btn_edit_bank';
  static const String editTheme = 'btn_edit_theme';
  static const String editLayout = 'btn_edit_layout';
  static const String editAddress = 'btn_edit_address';
  static const String editLogo = 'btn_edit_logo';
  static const String changeCurrency = 'btn_change_currency';

  // === THEMES ===
  static const String themeClassic = 'theme_classic';
  static const String themeBeige = 'theme_beige';

  // === LAYOUTS ===
  static const String layoutLegacy = 'theme_layout_1';
  static const String layoutSignature = 'theme_layout_2';
  static const String layoutSimple = 'theme_layout_3';
  static const String layoutCorporate = 'theme_layout_4';

  // === SUBSCRIPTION ===
  static const String upgrade = 'btn_upgrade';
  static const String monthly = 'btn_monthly';
  static const String yearly = 'btn_yearly';
  static const String verifyPayment = 'btn_verify_payment';
  static const String subStatus = 'btn_sub_status';

  // === TEAM MANAGEMENT ===
  static const String manageTeam = 'btn_manage_team';
  static const String removeTeamMemberPrefix = 'rm_';
  static const String confirmRemovePrefix = 'confirm_rm_';

  // === STATS ===
  static const String stats = 'btn_stats';
  static const String statsWeekly = 'btn_stats_weekly';
  static const String statsMonthly = 'btn_stats_monthly';
  static const String statsYearly = 'btn_stats_yearly';
  static const String statsAllTime = 'btn_stats_all_time';
}

/// Shared menu option definitions to avoid duplication.
abstract class MenuOptions {
  /// Edit Profile menu options - single source of truth.
  static List<Map<String, String>> get editProfile => [
        {'id': ButtonIds.editName, 'title': 'Business Name'},
        {'id': ButtonIds.editPhone, 'title': 'Phone Number'},
        {'id': ButtonIds.editBank, 'title': 'Bank Details'},
        {'id': ButtonIds.editTheme, 'title': 'Theme (Color)'},
        {'id': ButtonIds.editLayout, 'title': 'Layout Structure'},
        {'id': ButtonIds.editAddress, 'title': 'Business Address'},
        {'id': ButtonIds.editLogo, 'title': 'Upload Logo'},
        {'id': ButtonIds.changeCurrency, 'title': 'Change Currency'},
      ];

  /// Short version of edit profile options (for post-action "loop back" menus).
  static List<Map<String, String>> get editProfileShort => [
        {'id': ButtonIds.editName, 'title': 'Business Name'},
        {'id': ButtonIds.editPhone, 'title': 'Phone Number'},
        {'id': ButtonIds.editBank, 'title': 'Bank Details'},
        {'id': ButtonIds.editTheme, 'title': 'Theme'},
        {'id': ButtonIds.editLayout, 'title': 'Layout'},
        {'id': ButtonIds.changeCurrency, 'title': 'Currency'},
        {'id': ButtonIds.editLogo, 'title': 'Upload Logo'},
        {'id': ButtonIds.editAddress, 'title': 'Business Address'},
      ];

  /// Theme selection options.
  static List<Map<String, String>> get themes => [
        {'id': ButtonIds.themeClassic, 'title': 'B&W (Classic)'},
        {'id': ButtonIds.themeBeige, 'title': 'Beige'},
      ];

  /// Settings menu options.
  static List<Map<String, String>> settingsMenu({required bool isPremium}) => [
        {'id': ButtonIds.editProfile, 'title': 'Edit Profile'},
        {'id': ButtonIds.manageTeam, 'title': 'Manage Team'},
        {'id': ButtonIds.stats, 'title': 'View Stats'},
        {'id': ButtonIds.help, 'title': 'Help & Support'},
        {'id': ButtonIds.subStatus, 'title': 'Subscription Status'},
        if (!isPremium)
          {'id': ButtonIds.upgrade, 'title': 'Upgrade to Premium'},
      ];
}

/// Pricing constants for subscription plans.
abstract class Pricing {
  // === PAYSTACK (NGN) ===
  static const int monthlyNgn = 3500;
  static const int annualNgn = 35000;
  static const int monthlyNgnKobo = 350000; // 3,500 * 100
  static const int annualNgnKobo = 3500000; // 35,000 * 100

  // === EARLY ACCESS PAYSTACK (NGN) ===
  static const int earlyAccessMaxUsers = 10;
  static const int earlyAccessMonthlyNgn = 2000;
  static const int earlyAccessAnnualNgn = 20000;
  static const int earlyAccessMonthlyNgnKobo = 200000; // 2,000 * 100
  static const int earlyAccessAnnualNgnKobo = 2000000; // 20,000 * 100

  // === INTERNATIONAL BASE PRICING (USD) ===
  static const int monthlyUsd = 18;
  static const int annualUsd = 200;

  /// Minimum kobo amount to consider a payment valid for Premium.
  /// Adjusted dynamically lower to accommodate Early Access users on renewal.
  static const int minimumValidPaymentKobo = 200000;
}
