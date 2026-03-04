import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class LemonSqueezyService {
  final String _apiKey;
  final String _storeId;
  final String _redirectUrl;
  final String _baseUrl = 'https://api.lemonsqueezy.com/v1';
  static const int _maxRetries = 2;
  static const Duration _timeout = Duration(seconds: 30);

  LemonSqueezyService({String? apiKey, String? storeId, String? redirectUrl})
      : _apiKey = apiKey ?? Platform.environment['LS_API_KEY'] ?? '',
        _storeId = storeId ?? Platform.environment['LS_STORE_ID'] ?? '',
        _redirectUrl = redirectUrl ?? Platform.environment['LS_REDIRECT_URL'] ?? 'https://wa.me/message' {
    if (_apiKey.isEmpty) {
      print('Warning: LS_API_KEY is missing.');
    }
    if (_storeId.isEmpty) {
      print('Warning: LS_STORE_ID is missing.');
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
        print('LemonSqueezy request failed (attempt ${attempt + 1}/$_maxRetries): $e. Retrying in ${delay.inMilliseconds}ms...');
        await Future.delayed(delay);
      }
    }
    throw Exception('LemonSqueezy request failed after $_maxRetries retries');
  }

  /// Creates a Lemon Squeezy checkout session for a variant and passes custom data.
  Future<String> createCheckout({
    required String email,
    required String variantId,
    required String phoneNumber,
    required String planName,
  }) async {
    final url = Uri.parse('$_baseUrl/checkouts');

    final response = await _requestWithRetry(() => http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/vnd.api+json',
        'Content-Type': 'application/vnd.api+json',
      },
      body: jsonEncode({
        'data': {
          'type': 'checkouts',
          'attributes': {
            'checkout_data': {
              'email': email,
              'custom': {
                'phoneNumber': phoneNumber,
                'planName': planName,
              },
            },
            'product_options': {
              'redirect_url': _redirectUrl,
            }
          },
          'relationships': {
            'store': {
              'data': {
                'type': 'stores',
                'id': _storeId,
              }
            },
            'variant': {
              'data': {
                'type': 'variants',
                'id': variantId,
              }
            }
          }
        }
      }),
    ));

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['data']['attributes']['url'] as String;
    } else {
      throw Exception(
          'Failed to create Lemon Squeezy checkout: ${response.statusCode} - ${response.body}');
    }
  }
}
