import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class LemonSqueezyService {
  final String _apiKey;
  final String _storeId;
  final String _baseUrl = 'https://api.lemonsqueezy.com/v1';

  LemonSqueezyService({String? apiKey, String? storeId})
      : _apiKey = apiKey ?? Platform.environment['LS_API_KEY'] ?? '',
        _storeId = storeId ?? Platform.environment['LS_STORE_ID'] ?? '' {
    if (_apiKey.isEmpty) {
      print('Warning: LS_API_KEY is missing.');
    }
    if (_storeId.isEmpty) {
      print('Warning: LS_STORE_ID is missing.');
    }
  }

  /// Creates a Lemon Squeezy checkout session for a variant and passes custom data.
  Future<String> createCheckout({
    required String email,
    required String variantId,
    required String phoneNumber,
    required String planName,
  }) async {
    final url = Uri.parse('$_baseUrl/checkouts');

    final response = await http.post(
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
              'redirect_url':
                  'https://your-success-url.com', // Optional: Replace with an actual success page if desired
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
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['data']['attributes']['url'] as String;
    } else {
      throw Exception(
          'Failed to create Lemon Squeezy checkout: ${response.statusCode} - ${response.body}');
    }
  }
}
