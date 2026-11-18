import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Verifies that a webhook request really came from Meta.
///
/// Meta signs every webhook POST with your App Secret and sends the result in
/// the `X-Hub-Signature-256` header as `sha256=<hex digest>`. If the digest we
/// compute from the raw body doesn't match, the request didn't come from Meta
/// (or was tampered with) and must be ignored.
class MetaSignature {
  static const String headerName = 'x-hub-signature-256';
  static const String _prefix = 'sha256=';

  /// Returns true only when [header] is a valid signature of [rawBody].
  static bool isValid({
    required String rawBody,
    required String? header,
    required String appSecret,
  }) {
    if (appSecret.isEmpty || header == null || !header.startsWith(_prefix)) {
      return false;
    }

    final expected = Hmac(sha256, utf8.encode(appSecret))
        .convert(utf8.encode(rawBody))
        .toString();
    final received = header.substring(_prefix.length).toLowerCase();

    return _constantTimeEquals(expected, received);
  }

  /// Compares two strings without leaking timing information.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
