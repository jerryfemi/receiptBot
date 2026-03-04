import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class PaystackService {
  final String secretKey;
  final String baseUrl = 'https://api.paystack.co';
  static const int _maxRetries = 2;
  static const Duration _timeout = Duration(seconds: 30);

  PaystackService({String? key})
      : secretKey = key ?? Platform.environment['PAYSTACK_SECRET_KEY'] ?? '' {
    if (secretKey.isEmpty) {
      print('Warning: PAYSTACK_SECRET_KEY is missing.');
    }
  }

  /// Internal HTTP helper with retry logic and timeout
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
        print('Paystack request failed (attempt ${attempt + 1}/$_maxRetries): $e. Retrying in ${delay.inMilliseconds}ms...');
        await Future.delayed(delay);
      }
    }
    throw Exception('Paystack request failed after $_maxRetries retries');
  }

  /// Initializes a transaction and returns the checkout URL and reference.
  Future<Map<String, String>> initializeTransaction({
    required String email,
    required double amount, // Amount in major currency (e.g. NGN)
    String currency = 'NGN',
  }) async {
    final url = Uri.parse('$baseUrl/transaction/initialize');

    // Paystack expects amount in the lowest denomination (e.g., kobo for NGN)
    final amountInKobo = (amount * 100).toInt();

    final response = await _requestWithRetry(() => http.post(
      url,
      headers: {
        'Authorization': 'Bearer $secretKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'amount': amountInKobo,
        'currency': currency,
      }),
    ));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == true) {
        return {
          'authorization_url': data['data']['authorization_url'] as String,
          'reference': data['data']['reference'] as String,
        };
      } else {
        throw Exception(
            "Paystack API returned false status: ${data['message']}");
      }
    } else {
      throw Exception(
          'Failed to initialize Paystack transaction: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> verifyTransaction(String reference) async {
    final url = Uri.parse('$baseUrl/transaction/verify/$reference');

    final response = await _requestWithRetry(() => http.get(
      url,
      headers: {
        'Authorization': 'Bearer $secretKey',
      },
    ));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['status'] == true) {
        return json['data'] as Map<String, dynamic>;
      } else {
        throw Exception("Paystack verify false status: ${json['message']}");
      }
    } else {
      throw Exception(
          'Failed to verify Paystack transaction: ${response.statusCode}');
    }
  }
}
