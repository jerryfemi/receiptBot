import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

enum OnboardingStatus {
  new_user,
  awaiting_setup_choice,
  awaiting_invite_code,
  awaiting_address,
  awaiting_phone,
  awaiting_logo,
  active,
}

enum UserRole { admin, agent }

enum UserAction {
  idle,
  createReceipt,
  editName,
  editPhone,
  editAddress,
  editLogo,
  createInvoice,
  editBankDetails,
  selectTheme,
  selectLayout, // New Action
  editProfileMenu,
  selectCurrency,
  awaitingInvoiceBankDetails,
  awaitingEmailForUpgrade,
  selectingSubscriptionPlan,
  removeTeamMember,
  confirmRemoveTeamMember, // Confirmation step before destructive action
}

enum TransactionType {
  receipt,
  invoice,
}

@JsonSerializable()
class BusinessProfile {
  final String phoneNumber;
  final String? orgId; // New Field: Link to Organization
  final UserRole role; // New Field: Admin or Agent
  final OnboardingStatus? status;
  final UserAction? currentAction; // New Field
  final String? businessName;
  final String? businessAddress;
  final String? displayPhoneNumber;
  final String? logoUrl;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;

  @JsonKey(fromJson: _transactionFromJson)
  final Transaction?
      pendingTransaction; // Temporary storage for theme selection

  final int? themeIndex; // Changed to nullable
  final int? layoutIndex; // New field for physical layout structure
  final String currencyCode; // e.g. NGN, USD, GBP
  final String currencySymbol; // e.g. ₦, $, £

  final bool isPremium;
  final DateTime? premiumExpiresAt;
  final String? email;
  final String? pendingPaymentReference;
  final String? pendingSubscriptionTier; // Add the missing field
  final int receiptCount; // New field for Freemium limit
  final String?
      lastReceiptMonth; // New field for Freemium tracking e.g., '2026-03'
  final bool hasSeenPremiumTip; // Tracks if they saw the post-receipt tip

  BusinessProfile({
    required this.phoneNumber,
    this.orgId,
    this.role = UserRole.admin,
    this.status = OnboardingStatus.new_user,
    this.currentAction = UserAction.idle,
    this.businessName,
    this.businessAddress,
    this.displayPhoneNumber,
    this.logoUrl,
    this.bankName,
    this.accountNumber,
    this.accountName,
    this.pendingTransaction,
    this.themeIndex, // Default is null
    this.layoutIndex = 0, // Default to layout 0
    this.currencyCode = 'NGN',
    this.currencySymbol = '₦',
    this.isPremium = false,
    this.premiumExpiresAt,
    this.email,
    this.pendingPaymentReference,
    this.pendingSubscriptionTier,
    this.receiptCount = 0,
    this.lastReceiptMonth,
    this.hasSeenPremiumTip = false,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) =>
      _$BusinessProfileFromJson(json);

  Map<String, dynamic> toJson() => _$BusinessProfileToJson(this);

  BusinessProfile copyWith({
    String? phoneNumber,
    String? orgId,
    UserRole? role,
    OnboardingStatus? status,
    UserAction? currentAction,
    String? businessName,
    String? businessAddress,
    String? displayPhoneNumber,
    String? logoUrl,
    String? bankName,
    String? accountNumber,
    String? accountName,
    Transaction? pendingTransaction,
    int? themeIndex,
    int? layoutIndex,
    String? currencyCode,
    String? currencySymbol,
    bool? isPremium,
    DateTime? premiumExpiresAt,
    String? email,
    String? pendingPaymentReference,
    String? pendingSubscriptionTier,
    int? receiptCount,
    String? lastReceiptMonth,
    bool? hasSeenPremiumTip,
  }) {
    return BusinessProfile(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      orgId: orgId ?? this.orgId,
      role: role ?? this.role,
      status: status ?? this.status,
      currentAction: currentAction ?? this.currentAction,
      businessName: businessName ?? this.businessName,
      businessAddress: businessAddress ?? this.businessAddress,
      displayPhoneNumber: displayPhoneNumber ?? this.displayPhoneNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      accountName: accountName ?? this.accountName,
      pendingTransaction: pendingTransaction ?? this.pendingTransaction,
      themeIndex: themeIndex ?? this.themeIndex,
      layoutIndex: layoutIndex ?? this.layoutIndex,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      isPremium: isPremium ?? this.isPremium,
      premiumExpiresAt: premiumExpiresAt ?? this.premiumExpiresAt,
      email: email ?? this.email,
      pendingPaymentReference:
          pendingPaymentReference ?? this.pendingPaymentReference,
      pendingSubscriptionTier:
          pendingSubscriptionTier ?? this.pendingSubscriptionTier,
      receiptCount: receiptCount ?? this.receiptCount,
      lastReceiptMonth: lastReceiptMonth ?? this.lastReceiptMonth,
      hasSeenPremiumTip: hasSeenPremiumTip ?? this.hasSeenPremiumTip,
    );
  }
}

Transaction? _transactionFromJson(dynamic json) {
  if (json == null) return null;
  if (json is String) {
    if (json.isEmpty) return null;
    try {
      return Transaction.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      print('Error parsing pendingTransaction string: $e');
      return null;
    }
  }
  if (json is Map<String, dynamic>) {
    return Transaction.fromJson(json);
  }
  return null;
}

@JsonSerializable()
class ReceiptItem {
  final String description;
  final double amount;
  final int quantity;

  ReceiptItem({
    required this.description,
    required this.amount,
    this.quantity = 1,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) =>
      _$ReceiptItemFromJson(json);

  Map<String, dynamic> toJson() => _$ReceiptItemToJson(this);
}

@JsonSerializable()
class Transaction {
  final String customerName;
  final String? customerAddress;
  final String? customerPhone;
  final List<ReceiptItem> items;
  final double totalAmount;
  final String? amountInWords;
  final DateTime date;
  final TransactionType type;
  final DateTime? dueDate;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;
  final double? tax; // New field

  Transaction({
    required this.customerName,
    this.customerAddress,
    this.customerPhone,
    required this.items,
    required this.totalAmount,
    this.amountInWords,
    required this.date,
    this.type = TransactionType.receipt,
    this.dueDate,
    this.bankName,
    this.accountNumber,
    this.accountName,
    this.tax,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) =>
      _$TransactionFromJson(json);

  Map<String, dynamic> toJson() => _$TransactionToJson(this);
}

@JsonSerializable()
class Organization {
  final String id;
  final String inviteCode;
  final String? businessName;
  final String? businessAddress;
  final String? displayPhoneNumber;
  final String? logoUrl;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;
  final int? themeIndex;
  final int? layoutIndex; // New field for physical layout structure
  final String currencyCode;
  final String currencySymbol;
  final bool isPremium;
  final DateTime? premiumExpiresAt;

  Organization({
    required this.id,
    required this.inviteCode,
    this.businessName,
    this.businessAddress,
    this.displayPhoneNumber,
    this.logoUrl,
    this.bankName,
    this.accountNumber,
    this.accountName,
    this.themeIndex,
    this.layoutIndex = 0, // Default to layout 0
    this.currencyCode = 'NGN',
    this.currencySymbol = '₦',
    this.isPremium = false,
    this.premiumExpiresAt,
  });

  factory Organization.fromJson(Map<String, dynamic> json) =>
      _$OrganizationFromJson(json);

  Map<String, dynamic> toJson() => _$OrganizationToJson(this);

  Organization copyWith({
    String? businessName,
    String? businessAddress,
    String? displayPhoneNumber,
    String? logoUrl,
    String? bankName,
    String? accountNumber,
    String? accountName,
    int? themeIndex,
    int? layoutIndex,
    String? currencyCode,
    String? currencySymbol,
    bool? isPremium,
    DateTime? premiumExpiresAt,
  }) {
    return Organization(
      id: id,
      inviteCode: inviteCode,
      businessName: businessName ?? this.businessName,
      businessAddress: businessAddress ?? this.businessAddress,
      displayPhoneNumber: displayPhoneNumber ?? this.displayPhoneNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      accountName: accountName ?? this.accountName,
      themeIndex: themeIndex ?? this.themeIndex,
      layoutIndex: layoutIndex ?? this.layoutIndex,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      isPremium: isPremium ?? this.isPremium,
      premiumExpiresAt: premiumExpiresAt ?? this.premiumExpiresAt,
    );
  }
}

class SalesLedgerStats {
  double totalRevenue;
  int receiptCount;
  Map<String, double> customerSpending;
  Map<String, double> dailyTotals;

  SalesLedgerStats({
    this.totalRevenue = 0.0,
    this.receiptCount = 0,
    Map<String, double>? customerSpending,
    Map<String, double>? dailyTotals,
  })  : customerSpending = customerSpending ?? {},
        dailyTotals = dailyTotals ?? {};
}
