import 'dart:convert';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:receipt_bot/models.dart';
import 'package:uuid/uuid.dart';

class FirestoreService {
  final String projectId;
  FirestoreApi? _firestoreApi;
  StorageApi? _storageApi;
  AutoRefreshingAuthClient? _authClient;

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
        // ignore: unnecessary_null_comparison
        if (value == null) return;
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
      themeIndex: int.tryParse(fields['themeIndex']?.integerValue ?? '0') ?? 0,
    );
  }
}
