import 'dart:io';

import 'package:pdf/widgets.dart' as pw;

/// Loads font files from `public/fonts` once and keeps them in memory.
///
/// Every layout asks for fonts by file name, so adding a layout only means
/// adding its `.ttf` files; nothing here changes.
abstract class DocumentFonts {
  static const String _folder = 'public/fonts';
  static final Map<String, pw.Font> _cache = {};

  /// The font in `public/fonts/<file>`, loaded on first use.
  static Future<pw.Font> load(String file) async {
    final cached = _cache[file];
    if (cached != null) return cached;

    final bytes = await File('$_folder/$file').readAsBytes();
    final font = pw.Font.ttf(bytes.buffer.asByteData());
    _cache[file] = font;
    return font;
  }

  /// Fonts used when a layout's own font lacks a character. Noto Sans covers
  /// the naira sign (₦) and other currency symbols several display fonts miss.
  static Future<List<pw.Font>> fallback() async =>
      [await load('NotoSans-Regular.ttf')];
}
