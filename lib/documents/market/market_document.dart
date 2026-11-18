import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/market/market_footer.dart';
import 'package:receipt_bot/documents/market/market_header.dart';
import 'package:receipt_bot/documents/market/market_style.dart';
import 'package:receipt_bot/documents/market/market_table.dart';

/// Default stamp colours: red for a receipt, blue for an invoice.
final PdfColor _receiptStamp = PdfColor.fromHex('#C8102E');
final PdfColor _invoiceStamp = PdfColor.fromHex('#1E4FBF');

const double _stubWidth = 92;
const double _perforationWidth = 14;

/// The Market pad layout: a page torn from a sales book, with the serial
/// number on a stub, a perforated edge, a ruled grid and a rubber stamp.
Future<pw.Page> buildMarketPage(DocumentData data, {PdfColor? stamp}) async {
  final s = await MarketStyle.load(
    stamp ?? (data.isInvoice ? _invoiceStamp : _receiptStamp),
  );

  return pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(
        _stubWidth + _perforationWidth + 22,
        30,
        30,
        24,
      ),
      theme: pw.ThemeData.withFont(
        base: s.sans,
        bold: s.sansBold,
        fontFallback: s.fallback,
      ),
      buildBackground: (context) => pw.FullPage(
        ignoreMargins: true,
        child: _stubAndPerforation(data, s),
      ),
    ),
    footer: (context) => _pageFooter(data, s, context),
    build: (context) => [
      marketHeader(data, s),
      pw.SizedBox(height: 20),
      ...marketTable(data, s),
      pw.SizedBox(height: 14),
      marketAmountInWords(data, s),
      marketBankBox(data, s),
      ...marketNotes(data, s),
      marketStampAndSignature(data, s),
    ],
  );
}

/// The grey stub with the serial number, and the punched tear line.
pw.Widget _stubAndPerforation(DocumentData data, MarketStyle s) {
  // unconstrained: lay the text out on one line before turning it, instead
  // of wrapping it to the stub's narrow width.
  pw.Widget vertical(String text, pw.TextStyle style) => pw.Transform.rotateBox(
        angle: math.pi / 2,
        unconstrained: true,
        child: pw.Text(text, style: style),
      );

  return pw.Container(
    color: MarketStyle.white,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          width: _stubWidth,
          color: MarketStyle.stub,
          padding: const pw.EdgeInsets.symmetric(vertical: 30),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              vertical(
                '№ ${data.serial}',
                s.entry(size: 26, bold: true, color: s.stamp)
                    .copyWith(letterSpacing: 2),
              ),
              vertical(
                'CUSTOMER COPY · KEEP SAFE',
                s.label(size: 11, spacing: 0.2).copyWith(font: s.sansMedium),
              ),
            ],
          ),
        ),
        pw.SizedBox(
          width: _perforationWidth,
          child: pw.Stack(
            fit: pw.StackFit.expand,
            children: [
              pw.Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: pw.Container(
                  width: 2,
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      left: pw.BorderSide(
                        color: MarketStyle.perforation,
                        width: 1.5,
                        style: pw.BorderStyle.dashed,
                      ),
                    ),
                  ),
                ),
              ),
              pw.Positioned(
                left: -4,
                top: 14,
                bottom: 14,
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: List.generate(
                    5,
                    (_) => pw.Container(
                      width: 8,
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: MarketStyle.hole,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.Expanded(child: pw.SizedBox()),
      ],
    ),
  );
}

pw.Widget _pageFooter(DocumentData data, MarketStyle s, pw.Context context) {
  final left = data.isInvoice ? '' : DocumentData.thanks.toUpperCase();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(left, style: s.label()),
        if (context.pagesCount > 1)
          pw.Text(
            'PAGE ${context.pageNumber} OF ${context.pagesCount}',
            style: s.label(),
          ),
      ],
    ),
  );
}
