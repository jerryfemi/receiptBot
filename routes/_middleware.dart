import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:receipt_bot/services/firestore_service.dart';

final String _projectId = Platform.environment['GOOGLE_PROJECT_ID'] ?? 'invoicemaker-b3876';

// Initialize the FirestoreService once
final _firestoreService = FirestoreService(projectId: _projectId);

Handler middleware(Handler handler) {
  return handler
      .use(requestLogger())
      // Inject FirestoreService so routes can use context.read<FirestoreService>()
      .use(provider<FirestoreService>((_) => _firestoreService))
      // Add CORS headers so a hosted web app (like Jaspr) can fetch the data
      .use(
        (handler) => (context) async {
          // If the request is an OPTIONS preflight, respond immediately with success
          if (context.request.method == HttpMethod.options) {
            return Response(
              statusCode: 204,
              headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
                'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
              },
            );
          }

          // Process the actual request
          final response = await handler(context);

          // Return the response with CORS headers applied
          return response.copyWith(
            headers: {
              ...response.headers,
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
              'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
            },
          );
        },
      );
}
