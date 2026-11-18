import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/studio/studio_body.dart';
import 'package:receipt_bot/documents/studio/studio_sidebar.dart';
import 'package:receipt_bot/documents/studio/studio_style.dart';

/// Receipts are electric blue, invoices deep emerald. Both are mid-tones,
/// so the usual black logo still reads on the sidebar.
final PdfColor _receiptBlue = PdfColor.fromHex('#2B37E0');
final PdfColor _invoiceGreen = PdfColor.fromHex('#0E7C66');

/// The Studio layout: a bold modern page with a full-height sidebar.
Future<pw.Page> buildStudioPage(DocumentData data, {PdfColor? accent}) async {
  final s = await StudioStyle.load(
    accent ?? (data.isInvoice ? _invoiceGreen : _receiptBlue),
  );

  return pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(studioSidebarWidth + 30, 34, 30, 26),
      theme: pw.ThemeData.withFont(
        base: s.sans,
        bold: s.sansSemiBold,
        fontFallback: s.fallback,
      ),
      buildBackground: (context) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Container(
          color: StudioStyle.white,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [studioSidebar(data, s), pw.Expanded(child: pw.SizedBox())],
          ),
        ),
      ),
    ),
    footer: (context) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (context.pageNumber == context.pagesCount)
            studioSignOff(data, s)
          else
            pw.SizedBox(),
          if (context.pagesCount > 1)
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: s.text(size: 10, color: StudioStyle.faint),
            ),
        ],
      ),
    ),
    build: (context) => [
      studioHeading(data, s),
      ...studioItems(data, s),
      studioTotals(data, s),
      ...studioNotes(data, s),
    ],
  );
}
