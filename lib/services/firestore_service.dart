import 'dart:convert';
import 'dart:math'; // For random generate
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:receipt_bot/models/models.dart';
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
}
