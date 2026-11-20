import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Talks to Bachs, the payment provider for Premium plans.
///
/// Everything comes from the environment, so moving from sandbox to live is
/// a matter of swapping values in Render:
///   BACHS_SECRET_KEY       sk_sandbox_... or sk_live_...
///   BACHS_PRODUCT_MONTHLY  prod_... (one-time product, 30 days)
///   BACHS_PRODUCT_YEARLY   prod_... (one-time product, 365 days)
///   BACHS_WEBHOOK_SECRET   signing secret of the webhook endpoint
class BachsService {
  BachsService()
      : _key = Platform.environment['BACHS_SECRET_KEY'] ?? '',
        monthlyProductId = Platform.environment['BACHS_PRODUCT_MONTHLY'] ?? '',
        yearlyProductId = Platform.environment['BACHS_PRODUCT_YEARLY'] ?? '';

  final String _key;
  final String monthlyProductId;
  final String yearlyProductId;

  static const _timeout = Duration(seconds: 30);

  bool get isConfigured =>
      _key.isNotEmpty && monthlyProductId.isNotEmpty && yearlyProductId.isNotEmpty;

  String get _baseUrl => _key.startsWith('sk_live_')
      ? 'https://api.bachs.io'
      : 'https://sandbox-api.bachs.io';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_key',
        'Content-Type': 'application/json',
      };

  String productFor(String plan) =>
      plan == 'monthly' ? monthlyProductId : yearlyProductId;

  /// The plan a product belongs to, or null if it isn't one of ours.
  String? planForProduct(String productId) {
    if (productId == monthlyProductId) return 'monthly';
    if (productId == yearlyProductId) return 'yearly';
    return null;
  }

  /// Creates a hosted checkout for [plan] and returns its id and URL.
  Future<({String checkoutId, String url})> createCheckout({
    required String phone,
    required String email,
    required String plan,
    required String currency,
    String? name,
  }) async {
    final body = {
      'product_cart': [
        {'product_id': productFor(plan), 'quantity': 1},
      ],
      'customer': {
        'email': email,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        'phone_number': phone.startsWith('+') ? phone : '+$phone',
      },
      'billing_currency': currency,
      'reference': 'remi_${phone}_${DateTime.now().millisecondsSinceEpoch}',
      'metadata': {'phone': phone, 'plan': plan},
      'expires_in_minutes': 120,
    };

    final response = await http
        .post(
          Uri.parse('$_baseUrl/v1/checkout-sessions'),
          headers: {..._headers, 'Idempotency-Key': body['reference']! as String},
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'Bachs checkout failed: ${response.statusCode} ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      checkoutId: data['checkout_id'] as String,
      url: data['checkout_url'] as String,
    );
  }

  /// Fetches a checkout session, used by the "Verify Payment" button.
  Future<Map<String, dynamic>> getCheckout(String checkoutId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/v1/checkout-sessions/$checkoutId'),
            headers: _headers)
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception(
          'Bachs checkout lookup failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Checks a webhook delivery: HMAC-SHA256 hex of "{timestamp}.{raw_body}",
  /// rejected if older than five minutes. The V2 header can carry several
  /// signatures while a secret is being rotated; any match is accepted.
  static bool verifySignature({
    required String secret,
    required String rawBody,
    String? signatureV2,
    String? signature,
    String? timestamp,
  }) {
    String? ts = timestamp;
    final candidates = <String>[];
    if (signatureV2 != null) {
      for (final part in signatureV2.split(',')) {
        final kv = part.trim().split('=');
        if (kv.length != 2) continue;
        if (kv[0] == 't') ts = kv[1];
        if (kv[0] == 'v1') candidates.add(kv[1]);
      }
    }
    if (signature != null) candidates.add(signature.trim());
    if (ts == null || candidates.isEmpty) return false;

    final seconds = int.tryParse(ts);
    if (seconds == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - seconds;
    if (age.abs() > 300) return false;

    final expected = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('$ts.$rawBody'))
        .toString();
    return candidates.any((c) => _sameText(c.toLowerCase(), expected));
  }

  static bool _sameText(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
