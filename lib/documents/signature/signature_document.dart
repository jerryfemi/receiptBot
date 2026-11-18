import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/signature/signature_footer.dart';
import 'package:receipt_bot/documents/signature/signature_header.dart';
import 'package:receipt_bot/documents/signature/signature_lines.dart';
import 'package:receipt_bot/documents/signature/signature_style.dart';

/// The Signature layout: an A4 page on ivory paper inside a double frame.
///
/// Built as a MultiPage, so a long list of items continues on a second page
/// with the same frame, and the sign-off only appears on the last page.
Future<pw.Page> buildSignaturePage(
  DocumentData data, {
  PdfColor? accent,
}) async {
  final s = await SignatureStyle.load(accent ?? PdfColor.fromHex('#6E1F2E'));

  // Frame: 18pt paper margin, a 1pt line, a 3pt gap, then a 0.5pt line.
  const frameInset = 18.0;
  return pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(66, 56, 66, 44),
      theme: pw.ThemeData.withFont(
        base: s.sans,
        bold: s.sansMedium,
        fontFallback: s.fallback,
      ),
      buildBackground: (context) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Container(
          color: SignatureStyle.paper,
          padding: const pw.EdgeInsets.all(frameInset),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: s.accent, width: 1),
            ),
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: s.accent, width: 0.5),
              ),
            ),
          ),
        ),
      ),
    ),
    footer: (context) => context.pageNumber == context.pagesCount
        ? signatureSignOff(s)
        : pw.SizedBox(),
    build: (context) => [
      signatureHeader(data, s),
      pw.SizedBox(height: 26),
      ...signatureItems(data, s),
      pw.SizedBox(height: 10),
      signatureTotals(data, s),
      pw.SizedBox(height: 26),
      signatureSettlement(data, s),
      pw.SizedBox(height: 20),
      ...signatureNotes(data, s),
    ],
  );
}
