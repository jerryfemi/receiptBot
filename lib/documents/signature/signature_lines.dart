import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/signature/signature_style.dart';
import 'package:receipt_bot/models/models.dart';

/// One widget per item, so a long list can flow onto a second page.
List<pw.Widget> signatureItems(DocumentData data, SignatureStyle s) {
  return [
    for (final item in data.transaction.items)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 14),
        child: _itemRow(item, data, s),
      ),
  ];
}

pw.Widget _itemRow(ReceiptItem item, DocumentData data, SignatureStyle s) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(item.description, style: s.serifText()),
          pw.SizedBox(height: 2),
          pw.Text(
            '${item.quantity} at ${data.money(item.amount)}',
            style: s.text(size: 10.5, color: SignatureStyle.muted),
          ),
        ],
      ),
      // Dotted leader between the item and its price, as on a menu.
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(left: 8, right: 8, bottom: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: SignatureStyle.leader,
                style: pw.BorderStyle.dotted,
              ),
            ),
          ),
        ),
      ),
      pw.Text(data.money(item.amount * item.quantity), style: s.serifText()),
    ],
  );
}

/// Subtotal, discount, tax and the total, set to the right.
pw.Widget signatureTotals(DocumentData data, SignatureStyle s) {
  pw.Widget line(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: s.text(color: SignatureStyle.muted)),
            pw.Text(value, style: s.text(color: SignatureStyle.muted)),
          ],
        ),
      );

  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 250,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (data.discount > 0 || data.tax > 0)
            line('Subtotal', data.money(data.subtotal)),
          if (data.discount > 0)
            line('Discount', '−${data.money(data.discount)}'),
          if (data.tax > 0) line('Tax', data.money(data.tax)),
          pw.SizedBox(height: 4),
          pw.Container(height: 0.5, color: SignatureStyle.ink),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                data.isInvoice ? 'BALANCE DUE' : 'TOTAL',
                style: s.label(color: SignatureStyle.ink),
              ),
              pw.Text(
                data.money(data.total),
                style: s.serifText(size: 28, color: s.accent),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
