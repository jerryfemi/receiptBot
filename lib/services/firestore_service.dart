import 'dart:convert';
import 'dart:math'; // For random generate
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/utils/constants.dart';
import 'package:uuid/uuid.dart';

class FirestoreService {
  final String projectId;
  FirestoreApi? _firestoreApi;
  StorageApi? _storageApi;
  AutoRefreshingAuthClient? _authClient;

  FirestoreApi? get firestoreApi => _firestoreApi;

  // ignore: unused_field
  final http.Client _client = http.Client();

  FirestoreService({required this.projectId});

  // --- 1. ROBUST INITIALIZATION ---
  Future<void> initialize([String? serviceAccountJson]) async {
    final scopes = [
      FirestoreApi.datastoreScope,
      StorageApi.devstorageReadWriteScope,
    ];

    if (serviceAccountJson != null && serviceAccountJson.isNotEmpty) {
      // LOCAL MODE
      final credentials =
          ServiceAccountCredentials.fromJson(serviceAccountJson);
      _authClient = await clientViaServiceAccount(credentials, scopes);
      print("✅ Authenticated via Service Account JSON");
    } else {
      // CLOUD RUN MODE
      try {
        _authClient =
            await clientViaApplicationDefaultCredentials(scopes: scopes);
        print(
            "✅ Authenticated via Application Default Credentials (Cloud Run)");
      } catch (e) {
        print("⚠️ Failed to get Default Credentials: $e");
        rethrow;
      }
    }

    if (_authClient != null) {
      _firestoreApi = FirestoreApi(_authClient!);
      _storageApi = StorageApi(_authClient!);
    }
  }

  // --- 2. SAFETY CHECK ---
  Future<void> _ensureInitialized() async {
    if (_firestoreApi == null) {
      print("🔄 Firestore not ready. Initializing now...");
      await initialize();
    }
  }

  // Helper
  String _userPath(String phoneNumber) {
    return 'projects/$projectId/databases/(default)/documents/users/$phoneNumber';
  }

  String _orgPath(String orgId) {
    return 'projects/$projectId/databases/(default)/documents/organizations/$orgId';
  }

  Future<BusinessProfile?> getProfile(String phoneNumber) async {
    await _ensureInitialized(); // Safety Check

    try {
      final doc = await _firestoreApi!.projects.databases.documents.get(
        _userPath(phoneNumber),
      );
      if (doc.fields == null) return null;
      return _profileFromFields(doc.fields!, phoneNumber);
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return null;
      }
      print('Error getting profile: $e');
      rethrow;
    }
  }

  /// Counts the total number of users currently marked as premium.
  /// Used to determine if the early access promotion is still available.
  Future<int> getPremiumUserCount() async {
    await _ensureInitialized();

    final query = RunQueryRequest(
      structuredQuery: StructuredQuery(
        from: [CollectionSelector(collectionId: 'users')],
        where: Filter(
          fieldFilter: FieldFilter(
            field: FieldReference(fieldPath: 'isPremium'),
            op: 'EQUAL',
            value: Value(booleanValue: true),
          ),
        ),
        select: Projection(fields: [FieldReference(fieldPath: 'isPremium')]), // Minimize payload
        limit: Pricing.earlyAccessMaxUsers, // Optimization: Stop counting once we reach max capacity
      ),
    );

    try {
      final results = await _firestoreApi!.projects.databases.documents.runQuery(
        query,
        'projects/$projectId/databases/(default)/documents',
      );
      
      // If no matching documents, result is often empty or has a result with no document.
      int count = 0;
      for (final result in results) {
        if (result.document != null) {
          count++;
        }
      }
      return count;
    } catch (e) {
      print('Error counting premium users: $e');
      // If it fails (e.g., missing index), return a high number to disable the deal safely
      return 100;
    }
  }

  Future<String?> findUserByPaymentReference(String reference) async {
    await _ensureInitialized();

    final query = RunQueryRequest(
      structuredQuery: StructuredQuery(
        from: [CollectionSelector(collectionId: 'users')],
        where: Filter(
          fieldFilter: FieldFilter(
            field: FieldReference(fieldPath: 'pendingPaymentReference'),
            op: 'EQUAL',
            value: Value(stringValue: reference),
          ),
        ),
        limit: 1,
      ),
    );

    try {
      final results =
          await _firestoreApi!.projects.databases.documents.runQuery(
        query,
        'projects/$projectId/databases/(default)/documents',
      );

      for (final result in results) {
        if (result.document != null) {
          final namePaths = result.document!.name!.split('/');
          return namePaths.last;
        }
      }
      return null;
    } catch (e) {
      print('Error finding user by payment reference: $e');
      return null;
    }
  }

  // --- ORGANIZATION METHODS ---

  Future<Organization?> getOrganization(String orgId) async {
    await _ensureInitialized();

    try {
      final doc = await _firestoreApi!.projects.databases.documents.get(
        _orgPath(orgId),
      );
      if (doc.fields == null) return null;
      return _orgFromFields(doc.fields!, orgId);
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return null; // Org doesn't exist
      }
      print('Error getting organization: $e');
      rethrow;
    }
  }

  Future<String?> findOrganizationByInviteCode(String inviteCode) async {
    await _ensureInitialized();

    // Requires structuredQuery to search collections
    final query = RunQueryRequest(
      structuredQuery: StructuredQuery(
        from: [CollectionSelector(collectionId: 'organizations')],
        where: Filter(
          fieldFilter: FieldFilter(
            field: FieldReference(fieldPath: 'inviteCode'),
            op: 'EQUAL',
            value: Value(stringValue: inviteCode),
          ),
        ),
        limit: 1,
      ),
    );

    try {
      final results =
          await _firestoreApi!.projects.databases.documents.runQuery(
        query,
        'projects/$projectId/databases/(default)/documents',
      );

      // runQuery returns a list of RunQueryResponse objects, one per matched doc
      for (final result in results) {
        if (result.document != null) {
          // Document name looks like: projects/X/databases/(default)/documents/organizations/Y
          final namePaths = result.document!.name!.split('/');
          final orgId = namePaths.last;
          return orgId;
        }
      }
      return null;
    } catch (e) {
      print('Error finding organization by invite code: $e');
      return null;
    }
  }

  Future<String> createOrganization(String businessName) async {
    await _ensureInitialized();

    final orgId = Uuid().v4();
    String inviteCode = _generateInviteCode();

    // Ensure uniqueness
    while (await findOrganizationByInviteCode(inviteCode) != null) {
      inviteCode = _generateInviteCode();
    }

    final fields = <String, Value>{
      'inviteCode': Value(stringValue: inviteCode),
      'businessName': Value(stringValue: businessName),
      'themeIndex': Value(integerValue: '0'), // Default theme
    };

    await _firestoreApi!.projects.databases.documents.patch(
      Document(fields: fields),
      _orgPath(orgId),
    );

    return orgId;
  }

  /// Returns a valid invite code for an organization.
  ///
  /// If the organization exists but has a missing/empty invite code,
  /// this method generates a new unique code, persists it, and returns it.
  Future<String?> ensureOrganizationInviteCode(String orgId) async {
    await _ensureInitialized();

    final org = await getOrganization(orgId);
    if (org == null) return null;

    final existingCode = org.inviteCode.trim().toUpperCase();
    if (existingCode.isNotEmpty) {
      return existingCode;
    }

    String inviteCode = _generateInviteCode();
    while (await findOrganizationByInviteCode(inviteCode) != null) {
      inviteCode = _generateInviteCode();
    }

    await updateOrganizationData(orgId, {'inviteCode': inviteCode});
    return inviteCode;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  Future<void> updateOrganizationData(
      String orgId, Map<String, dynamic> data) async {
    await _ensureInitialized();

    final fields = <String, Value>{};
    data.forEach((key, value) {
      if (value is String) {
        fields[key] = Value(stringValue: value);
      } else if (value is int) {
        fields[key] = Value(integerValue: value.toString());
      } else if (value is double) {
        fields[key] = Value(doubleValue: value);
      } else if (value is bool) {
        fields[key] = Value(booleanValue: value);
      }
    });

    if (fields.isEmpty) return;

    await _firestoreApi!.projects.databases.documents.patch(
      Document(fields: fields),
      _orgPath(orgId),
      updateMask_fieldPaths: fields.keys.toList(),
    );
  }

  Future<List<BusinessProfile>> getTeamMembers(String orgId) async {
    await _ensureInitialized();

    final query = RunQueryRequest(
      structuredQuery: StructuredQuery(
        from: [CollectionSelector(collectionId: 'users')],
        where: Filter(
          fieldFilter: FieldFilter(
            field: FieldReference(fieldPath: 'orgId'),
            op: 'EQUAL',
            value: Value(stringValue: orgId),
          ),
        ),
      ),
    );

    try {
      final results =
          await _firestoreApi!.projects.databases.documents.runQuery(
        query,
        'projects/$projectId/databases/(default)/documents',
      );

      final members = <BusinessProfile>[];
      for (final result in results) {
        if (result.document != null && result.document!.fields != null) {
          final namePaths = result.document!.name!.split('/');
          final phone = namePaths.last;
          members.add(_profileFromFields(result.document!.fields!, phone));
        }
      }
      return members;
    } catch (e) {
      print('Error finding team members by orgId: $e');
      return [];
    }
  }

  Future<void> removeTeamMember(String phoneNumber) async {
    await _ensureInitialized();
    final fields = <String, Value>{
      'orgId': Value(stringValue: ''), // Clear orgId
      'role': Value(stringValue: UserRole.admin.name), // Reset to admin
      'currentAction': Value(stringValue: UserAction.idle.name),
    };

    await _firestoreApi!.projects.databases.documents.patch(
      Document(fields: fields),
      _userPath(phoneNumber),
      updateMask_fieldPaths: fields.keys.toList(),
    );
  }

  Future<void> updateOnboardingStep(
    String phoneNumber,
    OnboardingStatus status, {
    Map<String, dynamic>? data,
  }) async {
    await _ensureInitialized(); // Safety Check

    final fields = <String, Value>{
      'status': Value(stringValue: status.name), // Convert Enum to String here
    };

    if (data != null) {
      data.forEach((key, value) {
        if (value == null) return;

        if (value is String) {
          fields[key] = Value(stringValue: value);
        } else if (value is int) {
          fields[key] = Value(integerValue: value.toString());
        } else if (value is double) {
          fields[key] = Value(doubleValue: value);
        } else if (value is bool) {
          fields[key] = Value(booleanValue: value);
        }
      });
    }

    final document = Document(fields: fields);

    await _firestoreApi!.projects.databases.documents.patch(
      document,
      _userPath(phoneNumber),
      updateMask_fieldPaths: fields.keys.toList(),
    );
  }

  Future<void> saveLogoUrl(String phoneNumber, String url) async {
    await _ensureInitialized(); // Safety Check
    await updateOnboardingStep(
      phoneNumber,
      OnboardingStatus.active,
      data: {'logoUrl': url},
    );
  }

  Future<void> updateAction(String phoneNumber, UserAction action) async {
    await _ensureInitialized(); // Safety Check

    final fields = {'currentAction': Value(stringValue: action.name)};

    await _firestoreApi!.projects.databases.documents.patch(
      Document(fields: fields),
      _userPath(phoneNumber),
      updateMask_fieldPaths: ['currentAction'],
    );
  }

  Future<void> updateProfileData(
      String phoneNumber, Map<String, dynamic> data) async {
    await _ensureInitialized(); // Safety Check

    final fields = <String, Value>{};
    data.forEach((key, value) {
      if (value is String) {
        fields[key] = Value(stringValue: value);
      } else if (value is int) {
        fields[key] = Value(integerValue: value.toString());
      } else if (value is double) {
        fields[key] = Value(doubleValue: value);
      } else if (value is bool) {
        fields[key] = Value(booleanValue: value);
      }
    });

    if (fields.isEmpty) return;

    await _firestoreApi!.projects.databases.documents.patch(
      Document(fields: fields),
      _userPath(phoneNumber),
      updateMask_fieldPaths: fields.keys.toList(),
    );
  }

  Future<String> uploadFile(
      String filePath, List<int> bytes, String contentType) async {
    await _ensureInitialized(); // Safety Check

    if (_storageApi == null) throw Exception('Storage not initialized');

    final activeProjectId =
        projectId.isEmpty ? 'invoicemaker-b3876' : projectId;
    final bucket = '$activeProjectId.firebasestorage.app';

    final uuid = Uuid().v4();
    // Use Stream.value which is robust for known byte lists
    final media = Media(Stream.fromIterable([bytes]), bytes.length,
        contentType: contentType);

    final object = Object(
      name: filePath,
      contentType: contentType,
      metadata: {'token': uuid},
    );

    // Use Resumable upload which manages connections better
    await _storageApi!.objects.insert(
      object,
      bucket,
      uploadMedia: media,
      uploadOptions: UploadOptions.resumable,
    );

    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(filePath)}?alt=media&token=$uuid';
  }

  // Helper
  BusinessProfile _profileFromFields(
      Map<String, Value> fields, String phoneNumber) {
    return BusinessProfile(
      phoneNumber: phoneNumber,
      orgId: fields['orgId']?.stringValue,
      role: UserRole.values.firstWhere(
        (e) => e.name == (fields['role']?.stringValue ?? 'admin'),
        orElse: () => UserRole.admin,
      ),
      status: OnboardingStatus.values.firstWhere(
        (e) => e.name == (fields['status']?.stringValue ?? 'new_user'),
        orElse: () => OnboardingStatus.new_user,
      ),
      currentAction: UserAction.values.firstWhere(
        (e) => e.name == (fields['currentAction']?.stringValue ?? 'idle'),
        orElse: () => UserAction.idle,
      ),
      businessName: fields['businessName']?.stringValue,
      businessAddress: fields['businessAddress']?.stringValue,
      displayPhoneNumber: fields['displayPhoneNumber']?.stringValue,
      logoUrl: fields['logoUrl']?.stringValue,
      bankName: fields['bankName']?.stringValue,
      accountNumber: fields['accountNumber']?.stringValue,
      accountName: fields['accountName']?.stringValue,
      pendingTransaction: fields['pendingTransaction']?.stringValue != null &&
              fields['pendingTransaction']!.stringValue!.isNotEmpty
          ? Transaction.fromJson(
              jsonDecode(fields['pendingTransaction']!.stringValue!)
                  as Map<String, dynamic>)
          : null,
      themeIndex: fields['themeIndex']?.integerValue != null
          ? int.tryParse(fields['themeIndex']!.integerValue!)
          : null,
      layoutIndex: fields['layoutIndex']?.integerValue != null
          ? int.tryParse(fields['layoutIndex']!.integerValue!)
          : null,
      currencyCode: fields['currencyCode']?.stringValue ?? 'NGN',
      currencySymbol: fields['currencySymbol']?.stringValue ?? '₦',
      isPremium: fields['isPremium']?.booleanValue ?? false,
      premiumExpiresAt: fields['premiumExpiresAt']?.timestampValue != null
          ? DateTime.tryParse(fields['premiumExpiresAt']!.timestampValue!)
          : fields['premiumExpiresAt']?.stringValue != null
              ? DateTime.tryParse(fields['premiumExpiresAt']!.stringValue!)
              : null,
      email: fields['email']?.stringValue,
      pendingPaymentReference: fields['pendingPaymentReference']?.stringValue,
      pendingSubscriptionTier: fields['pendingSubscriptionTier']?.stringValue,
      receiptCount: fields['receiptCount']?.integerValue != null
          ? int.tryParse(fields['receiptCount']!.integerValue!) ?? 0
          : 0,
      lastReceiptMonth: fields['lastReceiptMonth']?.stringValue,
      hasSeenPremiumTip: fields['hasSeenPremiumTip']?.booleanValue ?? false,
    );
  }

  Organization _orgFromFields(Map<String, Value> fields, String orgId) {
    return Organization(
      id: orgId,
      inviteCode: fields['inviteCode']?.stringValue ?? '',
      businessName: fields['businessName']?.stringValue,
      businessAddress: fields['businessAddress']?.stringValue,
      displayPhoneNumber: fields['displayPhoneNumber']?.stringValue,
      logoUrl: fields['logoUrl']?.stringValue,
      bankName: fields['bankName']?.stringValue,
      accountNumber: fields['accountNumber']?.stringValue,
      accountName: fields['accountName']?.stringValue,
      themeIndex: fields['themeIndex']?.integerValue != null
          ? int.tryParse(fields['themeIndex']!.integerValue!)
          : null,
      layoutIndex: fields['layoutIndex']?.integerValue != null
          ? int.tryParse(fields['layoutIndex']!.integerValue!)
          : null,
      currencyCode: fields['currencyCode']?.stringValue ?? 'NGN',
      currencySymbol: fields['currencySymbol']?.stringValue ?? '₦',
      isPremium: fields['isPremium']?.booleanValue ?? false,
      premiumExpiresAt: fields['premiumExpiresAt']?.timestampValue != null
          ? DateTime.tryParse(fields['premiumExpiresAt']!.timestampValue!)
          : null,
    );
  }

  // --- SALES LEDGER ---

  Future<void> addSalesLedgerEntry(
    String ownerId,
    String receiptId,
    String customerName,
    double amount,
    String currency,
    DateTime createdAt,
  ) async {
    await _ensureInitialized();
    final fields = <String, Value>{
      'owner_id': Value(stringValue: ownerId),
      'receipt_id': Value(stringValue: receiptId),
      'customer_name': Value(stringValue: customerName),
      'amount': Value(doubleValue: amount),
      'currency': Value(stringValue: currency),
      'created_at': Value(timestampValue: createdAt.toUtc().toIso8601String()),
    };

    await _firestoreApi!.projects.databases.documents.createDocument(
      Document(fields: fields),
      'projects/$projectId/databases/(default)/documents',
      'sales_ledger',
    );
  }

  Future<Map<String, SalesLedgerStats>> getSalesStats(
      String ownerId, DateTime start, DateTime end) async {
    await _ensureInitialized();
    final query = RunQueryRequest(
      structuredQuery: StructuredQuery(
        from: [CollectionSelector(collectionId: 'sales_ledger')],
        where: Filter(
            compositeFilter: CompositeFilter(
          op: 'AND',
          filters: [
            Filter(
                fieldFilter: FieldFilter(
              field: FieldReference(fieldPath: 'owner_id'),
              op: 'EQUAL',
              value: Value(stringValue: ownerId),
            )),
            Filter(
                fieldFilter: FieldFilter(
              field: FieldReference(fieldPath: 'created_at'),
              op: 'GREATER_THAN_OR_EQUAL',
              value: Value(timestampValue: start.toUtc().toIso8601String()),
            )),
            Filter(
                fieldFilter: FieldFilter(
              field: FieldReference(fieldPath: 'created_at'),
              op: 'LESS_THAN_OR_EQUAL',
              value: Value(timestampValue: end.toUtc().toIso8601String()),
            )),
          ],
        )),
      ),
    );

    final results = await _firestoreApi!.projects.databases.documents.runQuery(
      query,
      'projects/$projectId/databases/(default)/documents',
    );

    final Map<String, SalesLedgerStats> currencyData = {};

    for (final result in results) {
      if (result.document?.fields != null) {
        final fields = result.document!.fields!;
        final amount = fields['amount']?.doubleValue ??
            double.tryParse(fields['amount']?.integerValue ?? '0') ??
            0.0;
        final currency = fields['currency']?.stringValue ?? 'NGN';
        final customerName = fields['customer_name']?.stringValue ?? 'Unknown';
        final createdAtStr = fields['created_at']?.timestampValue;

        if (createdAtStr != null) {
          final createdAt = DateTime.parse(createdAtStr).toLocal();
          final dayKey =
              "${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}";

          if (!currencyData.containsKey(currency)) {
            currencyData[currency] = SalesLedgerStats();
          }

          final data = currencyData[currency]!
          ..totalRevenue += amount
          ..receiptCount += 1;
          data.customerSpending[customerName] =
              (data.customerSpending[customerName] ?? 0.0) + amount;
          data.dailyTotals[dayKey] = (data.dailyTotals[dayKey] ?? 0.0) + amount;
        }
      }
    }

    return currencyData;
  }

  // --- WEBHOOK IDEMPOTENCY ---

  String _webhookPath(String reference) {
    return 'projects/$projectId/databases/(default)/documents/processed_webhooks/$reference';
  }

  /// Check if a webhook reference has already been processed
  Future<bool> isWebhookProcessed(String reference) async {
    await _ensureInitialized();
    try {
      await _firestoreApi!.projects.databases.documents
          .get(_webhookPath(reference));
      return true; // Document exists = already processed
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return false;
      }
      print('Error checking webhook idempotency: $e');
      return false; // Fail open to avoid blocking legitimate webhooks
    }
  }

  /// Mark a webhook reference as processed (with TTL via timestamp for cleanup)
  Future<void> markWebhookProcessed(String reference, String provider) async {
    await _ensureInitialized();
    try {
      final fields = <String, Value>{
        'provider': Value(stringValue: provider),
        'processedAt':
            Value(timestampValue: DateTime.now().toUtc().toIso8601String()),
      };

      final doc = Document(fields: fields);
      await _firestoreApi!.projects.databases.documents.createDocument(
        doc,
        'projects/$projectId/databases/(default)/documents',
        'processed_webhooks',
        documentId: reference,
      );
    } catch (e) {
      // If it fails due to already existing, that's fine (race condition protection)
      if (!e.toString().contains('ALREADY_EXISTS')) {
        print('Error marking webhook as processed: $e');
      }
    }
  }
}
