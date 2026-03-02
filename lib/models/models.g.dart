// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BusinessProfile _$BusinessProfileFromJson(Map<String, dynamic> json) =>
    BusinessProfile(
      phoneNumber: json['phoneNumber'] as String,
      orgId: json['orgId'] as String?,
      role: $enumDecodeNullable(_$UserRoleEnumMap, json['role']) ??
          UserRole.admin,
      status: $enumDecodeNullable(_$OnboardingStatusEnumMap, json['status']) ??
          OnboardingStatus.new_user,
      currentAction:
          $enumDecodeNullable(_$UserActionEnumMap, json['currentAction']) ??
              UserAction.idle,
      businessName: json['businessName'] as String?,
      businessAddress: json['businessAddress'] as String?,
      displayPhoneNumber: json['displayPhoneNumber'] as String?,
      logoUrl: json['logoUrl'] as String?,
      bankName: json['bankName'] as String?,
      accountNumber: json['accountNumber'] as String?,
      accountName: json['accountName'] as String?,
      pendingTransaction: _transactionFromJson(json['pendingTransaction']),
      themeIndex: (json['themeIndex'] as num?)?.toInt(),
      layoutIndex: (json['layoutIndex'] as num?)?.toInt() ?? 0,
      currencyCode: json['currencyCode'] as String? ?? 'NGN',
      currencySymbol: json['currencySymbol'] as String? ?? '₦',
      isPremium: json['isPremium'] as bool? ?? false,
      premiumExpiresAt: json['premiumExpiresAt'] == null
          ? null
          : DateTime.parse(json['premiumExpiresAt'] as String),
      email: json['email'] as String?,
      pendingPaymentReference: json['pendingPaymentReference'] as String?,
      pendingSubscriptionTier: json['pendingSubscriptionTier'] as String?,
      receiptCount: (json['receiptCount'] as num?)?.toInt() ?? 0,
      lastReceiptMonth: json['lastReceiptMonth'] as String?,
    );

Map<String, dynamic> _$BusinessProfileToJson(BusinessProfile instance) =>
    <String, dynamic>{
      'phoneNumber': instance.phoneNumber,
      'orgId': instance.orgId,
      'role': _$UserRoleEnumMap[instance.role]!,
      'status': _$OnboardingStatusEnumMap[instance.status],
      'currentAction': _$UserActionEnumMap[instance.currentAction],
      'businessName': instance.businessName,
      'businessAddress': instance.businessAddress,
      'displayPhoneNumber': instance.displayPhoneNumber,
      'logoUrl': instance.logoUrl,
      'bankName': instance.bankName,
      'accountNumber': instance.accountNumber,
      'accountName': instance.accountName,
      'pendingTransaction': instance.pendingTransaction,
      'themeIndex': instance.themeIndex,
      'layoutIndex': instance.layoutIndex,
      'currencyCode': instance.currencyCode,
      'currencySymbol': instance.currencySymbol,
      'isPremium': instance.isPremium,
      'premiumExpiresAt': instance.premiumExpiresAt?.toIso8601String(),
      'email': instance.email,
      'pendingPaymentReference': instance.pendingPaymentReference,
      'pendingSubscriptionTier': instance.pendingSubscriptionTier,
      'receiptCount': instance.receiptCount,
      'lastReceiptMonth': instance.lastReceiptMonth,
    };

const _$UserRoleEnumMap = {
  UserRole.admin: 'admin',
  UserRole.agent: 'agent',
};

const _$OnboardingStatusEnumMap = {
  OnboardingStatus.new_user: 'new_user',
  OnboardingStatus.awaiting_setup_choice: 'awaiting_setup_choice',
  OnboardingStatus.awaiting_invite_code: 'awaiting_invite_code',
  OnboardingStatus.awaiting_address: 'awaiting_address',
  OnboardingStatus.awaiting_phone: 'awaiting_phone',
  OnboardingStatus.awaiting_logo: 'awaiting_logo',
  OnboardingStatus.active: 'active',
};

const _$UserActionEnumMap = {
  UserAction.idle: 'idle',
  UserAction.createReceipt: 'createReceipt',
  UserAction.editName: 'editName',
  UserAction.editPhone: 'editPhone',
  UserAction.editAddress: 'editAddress',
  UserAction.editLogo: 'editLogo',
  UserAction.createInvoice: 'createInvoice',
  UserAction.editBankDetails: 'editBankDetails',
  UserAction.selectTheme: 'selectTheme',
  UserAction.selectLayout: 'selectLayout',
  UserAction.editProfileMenu: 'editProfileMenu',
  UserAction.selectCurrency: 'selectCurrency',
  UserAction.awaitingInvoiceBankDetails: 'awaitingInvoiceBankDetails',
  UserAction.awaitingEmailForUpgrade: 'awaitingEmailForUpgrade',
  UserAction.selectingSubscriptionPlan: 'selectingSubscriptionPlan',
};

ReceiptItem _$ReceiptItemFromJson(Map<String, dynamic> json) => ReceiptItem(
      description: json['description'] as String,
      amount: (json['amount'] as num).toDouble(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    );

Map<String, dynamic> _$ReceiptItemToJson(ReceiptItem instance) =>
    <String, dynamic>{
      'description': instance.description,
      'amount': instance.amount,
      'quantity': instance.quantity,
    };

Transaction _$TransactionFromJson(Map<String, dynamic> json) => Transaction(
      customerName: json['customerName'] as String,
      customerAddress: json['customerAddress'] as String?,
      customerPhone: json['customerPhone'] as String?,
      items: (json['items'] as List<dynamic>)
          .map((e) => ReceiptItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalAmount: (json['totalAmount'] as num).toDouble(),
      amountInWords: json['amountInWords'] as String?,
      date: DateTime.parse(json['date'] as String),
      type: $enumDecodeNullable(_$TransactionTypeEnumMap, json['type']) ??
          TransactionType.receipt,
      dueDate: json['dueDate'] == null
          ? null
          : DateTime.parse(json['dueDate'] as String),
      bankName: json['bankName'] as String?,
      accountNumber: json['accountNumber'] as String?,
      accountName: json['accountName'] as String?,
      tax: (json['tax'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$TransactionToJson(Transaction instance) =>
    <String, dynamic>{
      'customerName': instance.customerName,
      'customerAddress': instance.customerAddress,
      'customerPhone': instance.customerPhone,
      'items': instance.items,
      'totalAmount': instance.totalAmount,
      'amountInWords': instance.amountInWords,
      'date': instance.date.toIso8601String(),
      'type': _$TransactionTypeEnumMap[instance.type]!,
      'dueDate': instance.dueDate?.toIso8601String(),
      'bankName': instance.bankName,
      'accountNumber': instance.accountNumber,
      'accountName': instance.accountName,
      'tax': instance.tax,
    };

const _$TransactionTypeEnumMap = {
  TransactionType.receipt: 'receipt',
  TransactionType.invoice: 'invoice',
};

Organization _$OrganizationFromJson(Map<String, dynamic> json) => Organization(
      id: json['id'] as String,
      inviteCode: json['inviteCode'] as String,
      businessName: json['businessName'] as String?,
      businessAddress: json['businessAddress'] as String?,
      displayPhoneNumber: json['displayPhoneNumber'] as String?,
      logoUrl: json['logoUrl'] as String?,
      bankName: json['bankName'] as String?,
      accountNumber: json['accountNumber'] as String?,
      accountName: json['accountName'] as String?,
      themeIndex: (json['themeIndex'] as num?)?.toInt(),
      layoutIndex: (json['layoutIndex'] as num?)?.toInt() ?? 0,
      currencyCode: json['currencyCode'] as String? ?? 'NGN',
      currencySymbol: json['currencySymbol'] as String? ?? '₦',
      isPremium: json['isPremium'] as bool? ?? false,
      premiumExpiresAt: json['premiumExpiresAt'] == null
          ? null
          : DateTime.parse(json['premiumExpiresAt'] as String),
    );

Map<String, dynamic> _$OrganizationToJson(Organization instance) =>
    <String, dynamic>{
      'id': instance.id,
      'inviteCode': instance.inviteCode,
      'businessName': instance.businessName,
      'businessAddress': instance.businessAddress,
      'displayPhoneNumber': instance.displayPhoneNumber,
      'logoUrl': instance.logoUrl,
      'bankName': instance.bankName,
      'accountNumber': instance.accountNumber,
      'accountName': instance.accountName,
      'themeIndex': instance.themeIndex,
      'layoutIndex': instance.layoutIndex,
      'currencyCode': instance.currencyCode,
      'currencySymbol': instance.currencySymbol,
      'isPremium': instance.isPremium,
      'premiumExpiresAt': instance.premiumExpiresAt?.toIso8601String(),
    };
