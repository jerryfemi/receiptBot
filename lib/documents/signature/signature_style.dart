import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_fonts.dart';

/// Fonts, colours and text styles for the Signature layout.
///
/// Fraunces (serif) for names and amounts, Pinyon Script for the title and
/// sign-off, Karla for small print, all on ivory paper with one accent.
class SignatureStyle {
  SignatureStyle._({
    required this.accent,
    required this.serif,
    required this.serifMedium,
    required this.serifItalic,
    required this.script,
    required this.sans,
    required this.sansMedium,
    required this.fallback,
  });

  static Future<SignatureStyle> load(PdfColor accent) async {
    return SignatureStyle._(
      accent: accent,
      serif: await DocumentFonts.load('Fraunces-Regular.ttf'),
      serifMedium: await DocumentFonts.load('Fraunces-Medium.ttf'),
      serifItalic: await DocumentFonts.load('Fraunces-Italic.ttf'),
      script: await DocumentFonts.load('PinyonScript-Regular.ttf'),
      sans: await DocumentFonts.load('Karla-Regular.ttf'),
      sansMedium: await DocumentFonts.load('Karla-Medium.ttf'),
      fallback: await DocumentFonts.fallback(),
    );
  }

  final PdfColor accent;
  final pw.Font serif;
  final pw.Font serifMedium;
  final pw.Font serifItalic;
  final pw.Font script;
  final pw.Font sans;
  final pw.Font sansMedium;
  final List<pw.Font> fallback;

  static final PdfColor paper = PdfColor.fromHex('#FBF8F3');
  static final PdfColor ink = PdfColor.fromHex('#2A1A1D');
  static final PdfColor muted = PdfColor.fromHex('#7A6A6D');
  static final PdfColor body = PdfColor.fromHex('#5E4E51');
  static final PdfColor faint = PdfColor.fromHex('#9A8A8D');
  static final PdfColor leader = PdfColor.fromHex('#B9A9AC');

  /// Small spaced capitals: "PREPARED FOR", "TOTAL".
  pw.TextStyle label({PdfColor? color, double size = 10}) => pw.TextStyle(
        font: sans,
        fontSize: size,
        letterSpacing: size * 0.18,
        color: color ?? muted,
        fontFallback: fallback,
      );

  pw.TextStyle text({
    double size = 12,
    PdfColor? color,
    bool medium = false,
  }) =>
      pw.TextStyle(
        font: medium ? sansMedium : sans,
        fontSize: size,
        color: color ?? ink,
        lineSpacing: size * 0.35,
        fontFallback: fallback,
      );

  pw.TextStyle serifText({
    double size = 15,
    PdfColor? color,
    bool medium = false,
    bool italic = false,
    double letterSpacing = 0,
  }) =>
      pw.TextStyle(
        font: italic ? serifItalic : (medium ? serifMedium : serif),
        fontSize: size,
        color: color ?? ink,
        letterSpacing: letterSpacing,
        fontFallback: fallback,
      );

  pw.TextStyle scriptText(double size) => pw.TextStyle(
        font: script,
        fontSize: size,
        color: accent,
        fontFallback: fallback,
      );
}
