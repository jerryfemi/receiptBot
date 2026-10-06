import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Centralized design tokens for consistent PDF layouts.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppColors {
  static const PdfColor secondaryText = PdfColors.grey700;
  static const PdfColor subtleText = PdfColors.grey500;
  static const PdfColor defaultTableBorder = PdfColors.black;
}

class AppTypography {
  static pw.TextStyle titleStyle({
    required pw.Font font,
    PdfColor color = PdfColors.black,
    double fontSize = 32.0,
  }) {
    return pw.TextStyle(
      font: font,
      fontSize: fontSize,
      color: color,
      fontWeight: pw.FontWeight.bold,
    );
  }

  static pw.TextStyle headerStyle({
    required pw.Font font,
    PdfColor color = PdfColors.black,
    double fontSize = 24.0,
  }) {
    return pw.TextStyle(
      font: font,
      fontSize: fontSize,
      color: color,
      fontWeight: pw.FontWeight.bold,
    );
  }

  static pw.TextStyle labelStyle({
    required pw.Font font,
    PdfColor color = PdfColors.black,
    double fontSize = 10.0,
  }) {
    return pw.TextStyle(
      font: font,
      fontSize: fontSize,
      color: color,
      fontWeight: pw.FontWeight.bold,
    );
  }

  static pw.TextStyle bodyStyle({
    required pw.Font font,
    PdfColor color = PdfColors.black,
    double fontSize = 10.0,
    bool isBold = false,
  }) {
    return pw.TextStyle(
      font: font,
      fontSize: fontSize,
      color: color,
      fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
  }
}
