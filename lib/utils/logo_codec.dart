import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Stores business logos inside Firestore instead of a storage bucket.
///
/// Logos are shrunk to fit [maxSide] pixels and saved as a PNG data URI
/// (`data:image/png;base64,...`) in the existing `logoUrl` field, so nothing
/// else in the data model has to change. A 400px PNG is usually 20–80 KB,
/// well under Firestore's 1 MB document limit.
class LogoCodec {
  static const int maxSide = 400;
  static const int maxEncodedBytes = 700 * 1024;
  static const String _prefix = 'data:image/png;base64,';

  /// Resizes [bytes] (any common image format) and returns a data URI.
  /// Throws [FormatException] if the file isn't a readable image.
  static String encode(List<int> bytes) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw const FormatException('Unsupported image format');
    }

    final resized = (decoded.width > maxSide || decoded.height > maxSide)
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxSide : null,
            height: decoded.height > decoded.width ? maxSide : null,
          )
        : decoded;

    final encoded = base64Encode(img.encodePng(resized, level: 9));
    if (encoded.length > maxEncodedBytes) {
      throw const FormatException('Logo is too large after resizing');
    }
    return '$_prefix$encoded';
  }

  static bool isDataUri(String value) => value.startsWith('data:');

  /// Returns the raw image bytes from a data URI created by [encode].
  static Uint8List decode(String dataUri) {
    final comma = dataUri.indexOf(',');
    return base64Decode(dataUri.substring(comma + 1));
  }
}
