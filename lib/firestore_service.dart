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
  final http.Client _client = http.Client();

  FirestoreService({required this.projectId});

  Future<void> initialize(String serviceAccountJson) async {
    final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
    final client = await clientViaServiceAccount(
      credentials,
      [
        FirestoreApi.datastoreScope,
        StorageApi.devstorageReadWriteScope,
      ],
    );
    _firestoreApi = FirestoreApi(client);
    _storageApi = StorageApi(client);
  }

  // Helper to format document path
  String _userPath(String phoneNumber) {
    return 'projects/$projectId/databases/(default)/documents/users/$phoneNumber';
  }

  Future<BusinessProfile?> getProfile(String phoneNumber) async {
    if (_firestoreApi == null) {
      throw Exception('FirestoreService not initialized');
    }

    try {
      final doc = await _firestoreApi!.projects.databases.documents.get(
        _userPath(phoneNumber),
      );

      if (doc.fields == null) return null;
      return _profileFromFields(doc.fields!, phoneNumber);
    } catch (e) {
      // Check for 404 or "Not Found" error string from Google APIs
      // Googleapis usually throws DetailedApiRequestError
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return null;
      }
      print('Error getting profile: $e');
      rethrow; // Rethrow other errors (network, auth, etc.)
    }
  }

  Future<void> updateOnboardingStep(
    String phoneNumber,
    OnboardingStatus status, {
    Map<String, dynamic>? data,
  }) async {
    if (_firestoreApi == null) {
      throw Exception('FirestoreService not initialized');
    }

    final fields = <String, Value>{
      'status': Value(stringValue: status.name),
    };

    if (data != null) {
      data.forEach((key, value) {
        if (value is String) {
          fields[key] = Value(stringValue: value);
        } else if (value is int) {
          fields[key] = Value(integerValue: value.toString());
        } else if (value is double) {
          fields[key] = Value(doubleValue: double.tryParse(value.toString()));
        }
      });
    }

    final document = Document(fields: fields);

    // We use patch to merge/update fields
    await _firestoreApi!.projects.databases.documents.patch(
      document,
      _userPath(phoneNumber),
      updateMask_fieldPaths: fields.keys.toList(),
    );
  }

  Future<void> saveLogoUrl(String phoneNumber, String url) async {
    await updateOnboardingStep(
      phoneNumber,
      OnboardingStatus.active,
      data: {'logoUrl': url},
    );
  }

  Future<void> updateAction(String phoneNumber, UserAction action) async {
    if (_firestoreApi == null) {
      throw Exception('FirestoreService not initialized');
    }

    final fields = {'currentAction': Value(stringValue: action.name)};

    await _firestoreApi!.projects.databases.documents.patch(
      Document(fields: fields),
      _userPath(phoneNumber),
      updateMask_fieldPaths: ['currentAction'],
    );
  }

  Future<void> updateProfileData(
      String phoneNumber, Map<String, dynamic> data) async {
    if (_firestoreApi == null) {
      throw Exception('FirestoreService not initialized');
    }

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

    await _firestoreApi!.projects.databases.documents.patch(
      Document(fields: fields),
      _userPath(phoneNumber),
      updateMask_fieldPaths: fields.keys.toList(),
    );
  }

  Future<String> uploadFile(
      String filePath, List<int> bytes, String contentType) async {
    if (_storageApi == null) {
      throw Exception('Storage not initialized');
    }

    final bucket = '$projectId.firebasestorage.app';
    final uuid = Uuid().v4();
    final media =
        Media(Stream.value(bytes), bytes.length, contentType: contentType);

    final object = Object(
      name: filePath,
      contentType: contentType,
      metadata: {'firebaseStorageDownloadTokens': uuid},
    );

    // Ensure bucket exists or fail? Assuming default bucket exists.
    await _storageApi!.objects.insert(
      object,
      bucket,
      uploadMedia: media,
    );

    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(filePath)}?alt=media&token=$uuid';
  }

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
