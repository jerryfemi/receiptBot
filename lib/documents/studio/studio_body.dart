import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/studio/studio_style.dart';
import 'package:receipt_bot/models/models.dart';

/// "Receipt" in huge type, then the facts in a two-column grid.
pw.Widget studioHeading(DocumentData data, StudioStyle s) {
  final due = data.dueDate;
  final facts = <(String, String, bool)>[
    if (data.customerName != null)
      (data.isInvoice ? 'Bill to' : 'For', data.customerName!, false),
    (data.isInvoice ? 'Issued' : 'Date', DocumentData.shortDate(data.date), false),
    (data.isInvoice ? 'Invoice no.' : 'Receipt no.', data.number, false),
    if (data.isInvoice)
      ('Due', due == null ? 'On receipt' : DocumentData.shortDate(due), true)
    else
      ('Items', '${_itemCount(data)}', false),
  ];

  pw.Widget fact((String, String, bool) f) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(f.$1, style: s.text(size: 11, color: StudioStyle.muted)),
          pw.SizedBox(height: 3),
          pw.Text(
            f.$2,
            style: s.text(size: 14, semiBold: true, color: f.$3 ? s.accent : null),
          ),
        ],
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(data.title, style: s.headline(60, tracking: -0.045)),
      pw.SizedBox(height: 20),
      for (var i = 0; i < facts.length; i += 2)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: fact(facts[i])),
              pw.SizedBox(width: 18),
              pw.Expanded(
                child: i + 1 < facts.length ? fact(facts[i + 1]) : pw.SizedBox(),
              ),
            ],
          ),
        ),
    ],
  );
}

int _itemCount(DocumentData data) =>
    data.transaction.items.fold(0, (sum, item) => sum + item.quantity);

/// A heavy rule, then one row per item.
List<pw.Widget> studioItems(DocumentData data, StudioStyle s) {
  return [
    pw.SizedBox(height: 12),
    pw.Container(height: 2.5, color: StudioStyle.ink),
    for (final item in data.transaction.items) _itemRow(item, data, s),
  ];
}

pw.Widget _itemRow(ReceiptItem item, DocumentData data, StudioStyle s) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 14),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: StudioStyle.hairline, width: 1)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(item.description, style: s.text(size: 14, semiBold: true)),
              pw.SizedBox(height: 3),
              pw.Text(
                '${item.quantity} × ${data.money(item.amount)}',
                style: s.text(size: 11, color: StudioStyle.muted),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Text(
          data.money(item.amount * item.quantity),
          style: s.headline(18, bold: true, tracking: -0.01),
        ),
      ],
    ),
  );
}

/// Subtotal, discount and tax in small grey type, then the total.
pw.Widget studioTotals(DocumentData data, StudioStyle s) {
  pw.Widget line(String label, String value, {bool accent = false}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: s.text(color: StudioStyle.muted)),
            pw.Text(
              value,
              style: s.text(color: accent ? s.accent : StudioStyle.muted),
            ),
          ],
        ),
      );

  final showBreakdown = data.discount > 0 || data.tax > 0;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.SizedBox(height: 12),
      if (showBreakdown) line('Subtotal', data.money(data.subtotal)),
      if (data.discount > 0)
        line('Discount', '−${data.money(data.discount)}', accent: true),
      if (data.tax > 0) line('Tax', data.money(data.tax)),
      pw.SizedBox(height: showBreakdown ? 8 : 0),
      pw.Container(height: 2.5, color: StudioStyle.ink),
      pw.SizedBox(height: 12),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            data.isInvoice ? 'Amount due' : 'Total',
            style: s.text(size: 13, semiBold: true),
          ),
          pw.Text(
            data.money(data.total),
            style: s.headline(30, color: s.accent, tracking: -0.03),
          ),
        ],
      ),
    ],
  );
}

/// Notes and terms the business added.
List<pw.Widget> studioNotes(DocumentData data, StudioStyle s) {
  final notes = data.transaction.notes?.trim() ?? '';
  final terms = data.transaction.terms?.trim() ?? '';
  pw.Widget block(String label, String body) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: s.text(size: 11, semiBold: true)),
            pw.SizedBox(height: 3),
            pw.Text(body, style: s.text(size: 11, color: StudioStyle.muted, lineSpacing: 3)),
          ],
        ),
      );
  return [
    if (notes.isNotEmpty) block('Notes', notes),
    if (terms.isNotEmpty) block('Terms', terms),
  ];
}

/// The sign-off at the foot of the last page.
pw.Widget studioSignOff(DocumentData data, StudioStyle s) {
  return pw.Text(
    data.isInvoice ? 'Quote ${data.number}\nwhen you pay.' : 'Thanks for\nbuying from us.',
    style: s.headline(17, bold: true, tracking: -0.01, height: 3),
  );
}
