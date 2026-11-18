import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/market/market_style.dart';

/// Business name and badge, then the NAME and DATE lines of the pad.
pw.Widget marketHeader(DocumentData data, MarketStyle s) {
  final badgeColor = data.isInvoice ? s.stamp : MarketStyle.ink;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (data.logo != null) ...[
            pw.SizedBox(
              height: 38,
              width: 38,
              child: pw.Image(data.logo!, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(data.name.toUpperCase(), style: s.display(size: 26)),
                if (data.contactLine.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(data.contactLine, style: s.text(size: 11, color: MarketStyle.muted)),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Container(
            color: badgeColor,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: pw.Text(
              data.isInvoice ? 'INVOICE' : 'RECEIPT',
              style: s.display(
                size: 13,
                heavy: false,
                color: MarketStyle.white,
                spacing: 0.14,
              ),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 22),
      pw.Row(
        children: [
          pw.Expanded(
            child: marketField(
              data.isInvoice ? 'BILL TO' : 'NAME',
              data.customerName ?? '',
              s,
            ),
          ),
          pw.SizedBox(width: 18),
          pw.Expanded(
            child: marketField(
              data.isInvoice ? 'ISSUED' : 'DATE',
              DocumentData.slashDate(data.date),
              s,
            ),
          ),
        ],
      ),
    ],
  );
}

/// A ruled line with a small label and a "handwritten" value on it.
pw.Widget marketField(String label, String value, MarketStyle s, {double size = 15}) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 3),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: MarketStyle.ink, width: 1)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: s.label()),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(value, style: s.entry(size: size, bold: true), maxLines: 2),
        ),
      ],
    ),
  );
}
