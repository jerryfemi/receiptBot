// import 'dart:convert';
// import 'package:googleapis/firestore/v1.dart';
// import 'package:googleapis_auth/auth_io.dart';

// import 'package:receipt_bot/models.dart';

// class SessionManager {
//   final String projectId;
//   FirestoreApi? _firestoreApi;
//   SessionManager({required this.projectId});

//   Future<void> initialize([String? serviceAccountJson]) async {
//     AutoRefreshingAuthClient client;
//     final scopes = [FirestoreApi.datastoreScope];

//     if (serviceAccountJson != null && serviceAccountJson.isNotEmpty) {
//       final credentials = ServiceAccountCredentials.fromJson(
//         serviceAccountJson,
//       );
//       client = await clientViaServiceAccount(credentials, scopes);
//     } else {
//       client = await clientViaApplicationDefaultCredentials(scopes: scopes);
//     }
//     _firestoreApi = FirestoreApi(client);
//   }

//   // Returns list of messages: [{"role": "user", "parts": [{"text": "..."}]}]
//   Future<List<Map<String, dynamic>>> getHistory(String phoneNumber) async {
//     if (_firestoreApi == null) throw Exception('Firestore not initialized');

//     try {
//       final doc = await _firestoreApi!.projects.databases.documents.get(
//         'projects/$projectId/databases/(default)/documents/sessions/$phoneNumber',
//       );

//       if (doc.fields == null || !doc.fields!.containsKey('messages')) {
//         return [];
//       }

//       final messagesArray = doc.fields!['messages']?.arrayValue?.values;
//       if (messagesArray == null) return [];

//       return messagesArray.map((value) {
//         final jsonStr = value.stringValue!;
//         return jsonDecode(jsonStr) as Map<String, dynamic>;
//       }).toList();
//     } catch (e) {
//       if (e.toString().contains('404')) return [];
//       rethrow;
//     }
//   }

//   Future<void> saveMessage(String phoneNumber, String role, String text) async {
//     if (_firestoreApi == null) throw Exception('Firestore not initialized');

//     // Firestore arrayUnion to append
//     final currentHistory = await getHistory(phoneNumber);
//     // Determine if we need to trim history (keep last 15 messages to save tokens)
//     if (currentHistory.length >= 15) {
//       currentHistory.removeAt(0); // Remove oldest
//     }

//     // We can't easily "append" with auto-trimming using just arrayUnion in one go via REST API
//     // without reading first (which we essentially did or will do usually).
//     // But to keep it simple and atomic, we'll just read-modify-write for now
//     // as traffic isn't massive yet.

//     // Simpler approach: Just read current (we likely just did), append, save.
//     // NOTE: For a real high-concurrency app, we'd want transactions, but for a
//     // single-user-thread this is fine.

//     // Re-read just to be safe or use what we have?
//     // Let's assume we rely on the flow: Get -> Chat -> Save(User) -> Save(Bot).
//     // Actually, appending is safer.

//     final docPath =
//         'projects/$projectId/databases/(default)/documents/sessions/$phoneNumber';

//     // We use a transform to APPEND if possible, or just merge.
//     // Actually googleapis Firestore API 'commit' with 'fieldTransforms' is best for appending.

//     // BUT! To implement "Trim old messages", we must read-modify-write.
//     // So let's stick to: Read (done in webhook) -> Modify list -> Write All.
//     // Wait, the hook calls getHistory.

//     // Let's make this method just "append" one message for now to be fast?
//     // OR allow passing the full list to save?
//     // Passing full list is safer for the storage logic we want (trimming).

//     // Let's change signature to saveHistory(List) or just rely on append.
//     // For simplicity of this "Phase 1":
//     // The previous plan said "saveMessage".
//     // Let's do a smart append that handles creation.

//     // Actually, "FieldTransform" `APPEND_MISSING_ELEMENTS` is good.
//     // But we want to just add.

//     // Let's just do a patch with merge.
//     // Fetch, Append, Slice, Save.

//     var history = await getHistory(phoneNumber);
//     history.add({
//       'role': role,
//       'parts': [
//         {'text': text},
//       ],
//     });

//     if (history.length > 20) {
//       history = history.sublist(history.length - 20); // Keep last 20
//     }

//     final values = history
//         .map((m) => Value(stringValue: jsonEncode(m)))
//         .toList();

//     final doc = Document(
//       fields: {
//         'messages': Value(arrayValue: ArrayValue(values: values)),
//         // Update timestamp to keep track of stale sessions?
//         'lastUpdated': Value(
//           timestampValue: DateTime.now().toUtc().toIso8601String(),
//         ),
//       },
//     );

//     await _firestoreApi!.projects.databases.documents.patch(
//       doc,
//       docPath,
//       updateMask_fieldPaths: ['messages', 'lastUpdated'],
//     );
//   }

//   Future<void> clearSession(String phoneNumber) async {
//     if (_firestoreApi == null) throw Exception('Firestore not initialized');
//     try {
//       await _firestoreApi!.projects.databases.documents.delete(
//         'projects/$projectId/databases/(default)/documents/sessions/$phoneNumber',
//       );
//     } catch (e) {
//       // Ignore if already deleted
//     }
//   }

//   Future<void> logTransaction(Transaction transaction, String userId) async {
//     if (_firestoreApi == null) throw Exception('Firestore not initialized');

//     final doc = Document(
//       fields: {
//         'userId': Value(stringValue: userId),
//         'amount': Value(doubleValue: transaction.totalAmount),
//         'date': Value(timestampValue: DateTime.now().toUtc().toIso8601String()),
//         'type': Value(stringValue: transaction.type.name),
//         // We can store more if needed, but this is for stats
//       },
//     );

//     await _firestoreApi!.projects.databases.documents.createDocument(
//       doc,
//       'projects/$projectId/databases/(default)/documents',
//       'transactions',
//     );
//   }
// }
