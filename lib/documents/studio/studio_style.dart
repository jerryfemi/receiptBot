import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_fonts.dart';

/// The Studio look: a dark sidebar with the headline number, big tight
/// Bricolage Grotesque type, and Instrument Sans for everything else.
class StudioStyle {
  StudioStyle._({
    required this.accent,
    required this.display,
    required this.displayBold,
    required this.sans,
    required this.sansMedium,
    required this.sansSemiBold,
    required this.fallback,
  });

  static Future<StudioStyle> load(PdfColor accent) async {
    return StudioStyle._(
      accent: accent,
      display: await DocumentFonts.load('BricolageGrotesque-ExtraBold.ttf'),
      displayBold: await DocumentFonts.load('BricolageGrotesque-Bold.ttf'),
      sans: await DocumentFonts.load('InstrumentSans-Regular.ttf'),
      sansMedium: await DocumentFonts.load('InstrumentSans-Medium.ttf'),
      sansSemiBold: await DocumentFonts.load('InstrumentSans-SemiBold.ttf'),
      fallback: await DocumentFonts.fallback(),
    );
  }

  final PdfColor accent;
  final pw.Font display;
  final pw.Font displayBold;
  final pw.Font sans;
  final pw.Font sansMedium;
  final pw.Font sansSemiBold;
  final List<pw.Font> fallback;

  static const PdfColor white = PdfColors.white;
  static final PdfColor ink = PdfColor.fromHex('#111114');
  static final PdfColor muted = PdfColor.fromHex('#74747F');
  static final PdfColor faint = PdfColor.fromHex('#9A9AA5');
  static final PdfColor hairline = PdfColor.fromHex('#E6E6EA');
  static final PdfColor sideMuted = PdfColor.fromHex('#A3A3AD');
  static final PdfColor sideSoft = PdfColor.fromHex('#D6D6DD');

  /// Big tight headline type. [tracking] is in em, as in the design.
  pw.TextStyle headline(
    double size, {
    PdfColor? color,
    bool bold = false,
    double tracking = -0.03,
    double? height,
  }) =>
      pw.TextStyle(
        font: bold ? displayBold : display,
        fontSize: size,
        color: color ?? ink,
        letterSpacing: size * tracking,
        lineSpacing: height,
        fontFallback: fallback,
      );

  pw.TextStyle text({
    double size = 12,
    PdfColor? color,
    bool semiBold = false,
    bool medium = false,
    double? lineSpacing,
  }) =>
      pw.TextStyle(
        font: semiBold ? sansSemiBold : (medium ? sansMedium : sans),
        fontSize: size,
        color: color ?? ink,
        lineSpacing: lineSpacing,
        fontFallback: fallback,
      );
}
