import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_fonts.dart';

/// The Till look: a thermal till slip in JetBrains Mono, all capitals.
class TillStyle {
  TillStyle._({
    required this.accent,
    required this.regular,
    required this.bold,
    required this.heavy,
    required this.fallback,
  });

  static Future<TillStyle> load(PdfColor accent) async {
    return TillStyle._(
      accent: accent,
      regular: await DocumentFonts.load('JetBrainsMono-Regular.ttf'),
      bold: await DocumentFonts.load('JetBrainsMono-Bold.ttf'),
      heavy: await DocumentFonts.load('JetBrainsMono-ExtraBold.ttf'),
      fallback: await DocumentFonts.fallback(),
    );
  }

  final PdfColor accent;
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font heavy;
  final List<pw.Font> fallback;

  static final PdfColor paper = PdfColor.fromHex('#FBFBF7');
  static final PdfColor backdrop = PdfColor.fromHex('#2B2B30');
  static final PdfColor ink = PdfColor.fromHex('#17171A');
  static final PdfColor grey = PdfColor.fromHex('#55555C');
  static final PdfColor faint = PdfColor.fromHex('#75757D');

  pw.TextStyle mono({
    double size = 12,
    PdfColor? color,
    bool isBold = false,
    bool isHeavy = false,
    double tracking = 0,
  }) =>
      pw.TextStyle(
        font: isHeavy ? heavy : (isBold ? bold : regular),
        fontSize: size,
        color: color ?? ink,
        letterSpacing: size * tracking,
        lineSpacing: size * 0.25,
        fontFallback: fallback,
      );
}
