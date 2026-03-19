import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FlutterwaveService {
  final String secretKey;
  final String baseUrl = 'https://api.flutterwave.com/v3';
  final String redirectUrl;
  static const int _maxRetries = 2;
  static const Duration _timeout = Duration(seconds: 30);

  FlutterwaveService({String? key, String? redirect})
      : secretKey = key ?? Platform.environment['FLW_SECRET_KEY'] ?? '',
        redirectUrl = redirect ??
            Platform.environment['FLW_REDIRECT_URL'] ??
            'https://wa.me/message' {
    if (secretKey.isEmpty) {
      print('Warning: FLW_SECRET_KEY is missing.');
    }
  }

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() requestFn,
  ) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final response = await requestFn().timeout(_timeout);
        return response;
      } catch (e) {
        if (attempt == _maxRetries) rethrow;
        final delay = Duration(milliseconds: 500 * (attempt + 1));
        print(
            'Flutterwave request failed (attempt ${attempt + 1}/$_maxRetries): $e. Retrying in ${delay.inMilliseconds}ms...');
        await Future<void>.delayed(delay);
      }
    }

    throw Exception('Flutterwave request failed after $_maxRetries retries');
  }

  Future<Map<String, String>> initializeTransaction({
    required String email,
    required num amount,
    required String currency,
    required String txRef,
    required String phoneNumber,
    required String planName,
  }) async {
    final url = Uri.parse('$baseUrl/payments');

    final response = await _requestWithRetry(
      () => http.post(
        url,
        headers: {
          'Authorization': 'Bearer $secretKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'tx_ref': txRef,
          'amount': amount,
          'currency': currency,
          'redirect_url': redirectUrl,
          'customer': {
            'email': email,
            'phonenumber': phoneNumber,
            'name': 'WhatsApp User',
          },
          'meta': {
            'phoneNumber': phoneNumber,
            'planName': planName,
          },
          'customizations': {
            'title': 'Receipt Bot Premium',
            'description': '$planName subscription upgrade',
          },
        }),
      ),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] == 'success' && data['data'] is Map<String, dynamic>) {
        final payload = data['data'] as Map<String, dynamic>;
        return {
          'link': payload['link'] as String,
          'tx_ref': txRef,
        };
      }

      throw Exception(
          'Flutterwave API returned non-success payload: ${response.body}');
    }

    throw Exception(
      'Failed to initialize Flutterwave transaction: ${response.statusCode} - ${response.body}',
    );
  }

  Future<Map<String, dynamic>> verifyTransaction(int transactionId) async {
    final url = Uri.parse('$baseUrl/transactions/$transactionId/verify');

    final response = await _requestWithRetry(
      () => http.get(
        url,
        headers: {
          'Authorization': 'Bearer $secretKey',
        },
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] == 'success' && data['data'] is Map<String, dynamic>) {
        return data['data'] as Map<String, dynamic>;
      }

      throw Exception(
          'Flutterwave verify returned non-success payload: ${response.body}');
    }

    throw Exception(
      'Failed to verify Flutterwave transaction: ${response.statusCode} - ${response.body}',
    );
  }
}
