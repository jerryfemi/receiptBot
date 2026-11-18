import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_fonts.dart';

/// The Market pad look: a carbon-copy sales book from a Lagos shop.
/// Condensed Archivo for print, Courier Prime for "handwritten" entries,
/// Caveat for the signature, and one stamp colour.
class MarketStyle {
  MarketStyle._({
    required this.stamp,
    required this.sans,
    required this.sansMedium,
    required this.sansBold,
    required this.condensed,
    required this.condensedHeavy,
    required this.mono,
    required this.monoBold,
    required this.hand,
    required this.fallback,
  });

  static Future<MarketStyle> load(PdfColor stamp) async {
    return MarketStyle._(
      stamp: stamp,
      sans: await DocumentFonts.load('Archivo-Regular.ttf'),
      sansMedium: await DocumentFonts.load('Archivo-Medium.ttf'),
      sansBold: await DocumentFonts.load('Archivo-Bold.ttf'),
      condensed: await DocumentFonts.load('ArchivoCondensed-Bold.ttf'),
      condensedHeavy: await DocumentFonts.load('ArchivoCondensed-ExtraBold.ttf'),
      mono: await DocumentFonts.load('CourierPrime-Regular.ttf'),
      monoBold: await DocumentFonts.load('CourierPrime-Bold.ttf'),
      hand: await DocumentFonts.load('Caveat-Medium.ttf'),
      fallback: await DocumentFonts.fallback(),
    );
  }

  /// Red for receipts (the PAID stamp), blue for invoices.
  final PdfColor stamp;
  final pw.Font sans;
  final pw.Font sansMedium;
  final pw.Font sansBold;
  final pw.Font condensed;
  final pw.Font condensedHeavy;
  final pw.Font mono;
  final pw.Font monoBold;
  final pw.Font hand;
  final List<pw.Font> fallback;

  static const PdfColor white = PdfColors.white;
  static final PdfColor ink = PdfColor.fromHex('#1B2440');
  static final PdfColor muted = PdfColor.fromHex('#6B7591');
  static final PdfColor rule = PdfColor.fromHex('#C9D6EA');
  static final PdfColor stub = PdfColor.fromHex('#F4F6F9');
  static final PdfColor perforation = PdfColor.fromHex('#9AA3BA');
  static final PdfColor hole = PdfColor.fromHex('#DCDDD8');
  static final PdfColor pen = PdfColor.fromHex('#1E3A6E');

  /// Small spaced capitals: field names and column heads.
  pw.TextStyle label({
    double size = 10,
    PdfColor? color,
    bool bold = false,
    double spacing = 0.12,
  }) =>
      pw.TextStyle(
        font: bold ? sansBold : sans,
        fontSize: size,
        color: color ?? muted,
        letterSpacing: size * spacing,
        fontFallback: fallback,
      );

  pw.TextStyle text({double size = 13, PdfColor? color, bool medium = false}) =>
      pw.TextStyle(
        font: medium ? sansMedium : sans,
        fontSize: size,
        color: color ?? ink,
        fontFallback: fallback,
      );

  /// What the shopkeeper "wrote" on the pad.
  pw.TextStyle entry({double size = 13, PdfColor? color, bool bold = false}) =>
      pw.TextStyle(
        font: bold ? monoBold : mono,
        fontSize: size,
        color: color ?? ink,
        fontFallback: fallback,
      );

  pw.TextStyle display({
    required double size,
    PdfColor? color,
    bool heavy = true,
    double spacing = 0.01,
  }) =>
      pw.TextStyle(
        font: heavy ? condensedHeavy : condensed,
        fontSize: size,
        color: color ?? ink,
        letterSpacing: size * spacing,
        fontFallback: fallback,
      );

  pw.TextStyle signature() => pw.TextStyle(
        font: hand,
        fontSize: 28,
        color: pen,
        fontFallback: fallback,
      );
}
