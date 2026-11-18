import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/market/market_style.dart';
import 'package:receipt_bot/models/models.dart';

const double _qtyWidth = 44;
const double _rateWidth = 96;
const double _amountWidth = 108;

/// The ruled QTY / DESCRIPTION / RATE / AMOUNT grid, one widget per row so
/// a long sale can continue on the next page.
List<pw.Widget> marketTable(DocumentData data, MarketStyle s) {
  final sym = data.currencySymbol;
  return [
    _headerRow(sym, s),
    for (final item in data.transaction.items) _itemRow(item, s),
    _blankRow(s),
    if (data.discount > 0)
      _adjustRow('LESS DISC.', '−${DocumentData.plain(data.discount)}', s),
    if (data.tax > 0) _adjustRow('ADD TAX', DocumentData.plain(data.tax), s),
    _totalRow(data, s),
  ];
}

/// Rows have a fixed height so every column line runs top to bottom.
/// Long descriptions get a taller row instead of overflowing.
double _rowHeight(String description) {
  final lines = (description.length / 34).ceil().clamp(1, 3);
  return 20.0 + lines * 14;
}

pw.BoxDecoration _rowBox({bool ruled = true}) => pw.BoxDecoration(
      border: pw.Border(
        left: pw.BorderSide(color: MarketStyle.ink, width: 1.5),
        right: pw.BorderSide(color: MarketStyle.ink, width: 1.5),
        bottom: ruled
            ? pw.BorderSide(color: MarketStyle.rule, width: 1)
            : pw.BorderSide.none,
      ),
    );

pw.Widget _headerRow(String sym, MarketStyle s) {
  final style = s.label(color: MarketStyle.white, bold: true, spacing: 0.14);
  pw.Widget cell(String t, {pw.Alignment align = pw.Alignment.centerLeft}) =>
      pw.Container(
        alignment: align,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8),
        child: pw.Text(t, style: style),
      );
  return pw.Container(
    height: 26,
    decoration: pw.BoxDecoration(
      color: MarketStyle.ink,
      border: pw.Border.all(color: MarketStyle.ink, width: 1.5),
    ),
    child: pw.Row(
      children: [
        pw.SizedBox(width: _qtyWidth, child: cell('QTY')),
        pw.Expanded(child: cell('DESCRIPTION')),
        pw.SizedBox(
          width: _rateWidth,
          child: cell('RATE', align: pw.Alignment.centerRight),
        ),
        pw.SizedBox(
          width: _amountWidth,
          child: cell('AMOUNT $sym'.trim(), align: pw.Alignment.centerRight),
        ),
      ],
    ),
  );
}

pw.Widget _itemRow(ReceiptItem item, MarketStyle s) {
  return pw.Container(
    height: _rowHeight(item.description),
    decoration: _rowBox(),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          width: _qtyWidth,
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              right: pw.BorderSide(color: MarketStyle.rule, width: 1),
            ),
          ),
          child: pw.Text('${item.quantity}', style: s.entry()),
        ),
        pw.Expanded(
          child: pw.Container(
            alignment: pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8),
            child: pw.Text(item.description, style: s.text(), maxLines: 3),
          ),
        ),
        pw.Container(
          width: _rateWidth,
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8),
          child: pw.Text(DocumentData.plain(item.amount), style: s.entry()),
        ),
        _amountCell(
          s,
          pw.Text(
            DocumentData.plain(item.amount * item.quantity),
            style: s.entry(),
          ),
        ),
      ],
    ),
  );
}

/// One empty ruled line under the items, like the unused lines of a pad.
pw.Widget _blankRow(MarketStyle s) {
  return pw.Container(
    height: 34,
    decoration: _rowBox(),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          width: _qtyWidth,
          decoration: pw.BoxDecoration(
            border: pw.Border(
              right: pw.BorderSide(color: MarketStyle.rule, width: 1),
            ),
          ),
        ),
        pw.Spacer(),
        _amountCell(s, pw.SizedBox()),
      ],
    ),
  );
}

pw.Widget _adjustRow(String label, String value, MarketStyle s) {
  return pw.Container(
    height: 30,
    decoration: _rowBox(ruled: false),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          child: pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8),
            child: pw.Text(label, style: s.label(spacing: 0.1)),
          ),
        ),
        _amountCell(
          s,
          pw.Text(value, style: s.entry(size: 12, color: MarketStyle.muted)),
        ),
      ],
    ),
  );
}

pw.Widget _totalRow(DocumentData data, MarketStyle s) {
  final label = data.isInvoice ? 'BALANCE DUE' : 'TOTAL';
  return pw.Container(
    height: 38,
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: MarketStyle.ink, width: 1.5),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          child: pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8),
            child: pw.Text(
              '$label ${data.currencySymbol}'.trim(),
              style: s.label(
                size: 12,
                color: MarketStyle.ink,
                bold: true,
                spacing: 0.14,
              ),
            ),
          ),
        ),
        _amountCell(
          s,
          pw.Text(
            DocumentData.plain(data.total),
            style: s.entry(size: 17, bold: true),
          ),
          fill: MarketStyle.stub,
        ),
      ],
    ),
  );
}

/// The amount column, set off by a double line in the stamp colour.
pw.Widget _amountCell(MarketStyle s, pw.Widget child, {PdfColor? fill}) {
  return pw.Container(
    width: _amountWidth,
    decoration: pw.BoxDecoration(
      border: pw.Border(left: pw.BorderSide(color: s.stamp, width: 0.7)),
    ),
    child: pw.Container(
      margin: const pw.EdgeInsets.only(left: 1.4),
      alignment: pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8),
      decoration: pw.BoxDecoration(
        color: fill,
        border: pw.Border(left: pw.BorderSide(color: s.stamp, width: 0.7)),
      ),
      child: child,
    ),
  );
}
