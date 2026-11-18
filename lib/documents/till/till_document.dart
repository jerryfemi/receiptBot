import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/till/till_parts.dart';
import 'package:receipt_bot/documents/till/till_style.dart';
import 'package:receipt_bot/models/models.dart';

/// Till's own stamp red, used when no accent is given.
final PdfColor _tillRed = PdfColor.fromHex('#C8102E');

const double _paperWidth = 340;
const double _backdropMargin = 18;

/// The Till layout: one long till slip with torn edges and a QR code.
///
/// The page is as tall as the slip, like a real till roll, so there is
/// never a second page however many items there are.
Future<pw.Page> buildTillPage(DocumentData data, {PdfColor? accent}) async {
  final s = await TillStyle.load(accent ?? _tillRed);

  return pw.Page(
    pageTheme: pw.PageTheme(
      pageFormat: const PdfPageFormat(
        _paperWidth + _backdropMargin * 2,
        double.infinity,
      ),
      margin: pw.EdgeInsets.zero,
      theme: pw.ThemeData.withFont(
        base: s.regular,
        bold: s.bold,
        fontFallback: s.fallback,
      ),
    ),
    build: (context) => pw.Container(
      color: TillStyle.backdrop,
      padding: const pw.EdgeInsets.all(_backdropMargin),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          tillTeeth(width: _paperWidth, top: true),
          pw.Container(
            width: _paperWidth,
            color: TillStyle.paper,
            padding: const pw.EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                ..._header(data, s),
                tillDash(),
                ..._items(data, s),
                tillDash(above: 12, below: 8),
                ..._totals(data, s),
                tillDash(above: 14, below: 12),
                _qrBlock(data, s),
                ..._notes(data, s),
              ],
            ),
          ),
          tillTeeth(width: _paperWidth, top: false),
        ],
      ),
    ),
  );
}

List<pw.Widget> _header(DocumentData data, TillStyle s) {
  final small = s.mono(size: 11);
  final date = data.date;
  final hasTime = date.hour != 0 || date.minute != 0;
  final dateText =
      DateFormat(hasTime ? 'dd/MM/yy HH:mm' : 'dd/MM/yy').format(date);
  final due = data.dueDate;
  final customer = data.customerName?.toUpperCase();

  return [
    pw.Text(
      data.name.toUpperCase(),
      textAlign: pw.TextAlign.center,
      style: s.mono(size: 22, isHeavy: true, tracking: 0.04),
    ),
    if (data.contactLine.isNotEmpty) ...[
      pw.SizedBox(height: 6),
      pw.Text(
        [
          if (data.businessAddress?.trim().isNotEmpty ?? false)
            data.businessAddress!.trim().toUpperCase(),
          if (data.businessPhone?.trim().isNotEmpty ?? false)
            'TEL ${data.businessPhone!.trim()}',
        ].join('\n'),
        textAlign: pw.TextAlign.center,
        style: s.mono(size: 11, color: TillStyle.grey),
      ),
    ],
    tillDash(above: 14, below: 10),
    pw.Center(
      child: pw.Container(
        color: data.isInvoice ? s.accent : TillStyle.ink,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: pw.Text(
          data.title.toUpperCase(),
          style: s.mono(color: TillStyle.paper, isBold: true, tracking: 0.24),
        ),
      ),
    ),
    pw.SizedBox(height: 10),
    tillLine(
      'NO  ${data.number}',
      data.isInvoice ? 'ISSUED ${DateFormat('dd/MM/yy').format(date)}' : dateText,
      style: small,
    ),
    if (data.isInvoice)
      tillLine(
        customer == null ? '' : 'BILL TO $customer',
        due == null ? 'DUE ON RECEIPT' : 'DUE ${DateFormat('dd/MM/yy').format(due)}',
        style: small,
        rightStyle: s.mono(size: 11, isBold: true),
      )
    else if (customer != null)
      pw.Text('CUST $customer', style: small),
  ];
}

List<pw.Widget> _items(DocumentData data, TillStyle s) {
  pw.Widget item(ReceiptItem i) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(i.description.toUpperCase(), style: s.mono(isBold: true)),
            tillLine(
              '  ${i.quantity} x ${DocumentData.plain(i.amount)}',
              DocumentData.plain(i.amount * i.quantity),
              style: s.mono(color: TillStyle.grey),
              rightStyle: s.mono(),
            ),
          ],
        ),
      );
  return [for (final i in data.transaction.items) item(i)];
}

List<pw.Widget> _totals(DocumentData data, TillStyle s) {
  final body = s.mono();
  final showBreakdown = data.discount > 0 || data.tax > 0;
  return [
    if (showBreakdown)
      tillLine('SUBTOTAL', DocumentData.plain(data.subtotal), style: body),
    if (data.discount > 0)
      tillLine('DISCOUNT', '-${DocumentData.plain(data.discount)}', style: body),
    if (data.tax > 0) tillLine('TAX', DocumentData.plain(data.tax), style: body),
    if (showBreakdown) tillDouble() else pw.SizedBox(height: 2),
    tillLine(
      '${data.isInvoice ? 'DUE' : 'TOTAL'} ${data.currencyCode}',
      DocumentData.plain(data.total),
      style: s.mono(size: 15, isHeavy: true),
      rightStyle: s.mono(
        size: 26,
        isHeavy: true,
        tracking: -0.02,
        color: data.isInvoice ? s.accent : null,
      ),
    ),
    pw.SizedBox(height: 14),
    if (data.isInvoice) _payTo(data, s) else _paidBox(s),
  ];
}

pw.Widget _paidBox(TillStyle s) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: s.accent, width: 2),
      ),
      child: pw.Text(
        '** PAID **',
        textAlign: pw.TextAlign.center,
        style: s.mono(size: 18, isHeavy: true, color: s.accent, tracking: 0.3),
      ),
    );

pw.Widget _payTo(DocumentData data, TillStyle s) {
  if (!data.hasBankDetails) return pw.SizedBox();
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: TillStyle.ink, width: 2),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('PAY TO', style: s.mono(size: 10, color: TillStyle.grey, tracking: 0.2)),
        pw.Text(data.accountNumber!, style: s.mono(size: 18, isHeavy: true, tracking: 0.06)),
        pw.Text(data.bankName!.toUpperCase(), style: s.mono()),
        if (data.accountName?.trim().isNotEmpty ?? false)
          pw.Text(data.accountName!.toUpperCase(), style: s.mono(color: TillStyle.grey)),
      ],
    ),
  );
}

/// A real QR code, with no caption. Receipts carry a summary of the sale;
/// invoices carry the payment details, so the customer can copy them
/// straight into their banking app.
pw.Widget _qrBlock(DocumentData data, TillStyle s) {
  final payload = data.isInvoice && data.hasBankDetails
      ? [
          'Pay ${data.money(data.total)} to ${data.name}',
          '${data.bankName} ${data.accountNumber}',
          if (data.accountName?.trim().isNotEmpty ?? false) data.accountName!.trim(),
          'Reference: ${data.number}',
        ].join('\n')
      : [
          '${data.name} ${data.title} ${data.number}',
          DocumentData.shortDate(data.date),
          'Total: ${data.money(data.total)}',
        ].join('\n');

  final qr = pw.BarcodeWidget(
    barcode: pw.Barcode.qrCode(),
    data: payload,
    width: 72,
    height: 72,
    color: TillStyle.ink,
    drawText: false,
  );

  // Invoices show the code on its own; receipts add the thank-you beside it.
  if (data.isInvoice) return pw.Center(child: qr);

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      qr,
      pw.SizedBox(width: 14),
      pw.Expanded(
        child: pw.Text(
          DocumentData.thanks.toUpperCase(),
          style: s.mono(size: 11),
        ),
      ),
    ],
  );
}

List<pw.Widget> _notes(DocumentData data, TillStyle s) {
  final notes = data.notes ?? '';
  final terms = data.terms ?? '';
  if (notes.isEmpty && terms.isEmpty) return [];
  return [
    tillDash(above: 12, below: 8),
    if (notes.isNotEmpty) pw.Text(notes.toUpperCase(), style: s.mono(size: 10, color: TillStyle.grey)),
    if (notes.isNotEmpty && terms.isNotEmpty) pw.SizedBox(height: 6),
    if (terms.isNotEmpty) pw.Text(terms.toUpperCase(), style: s.mono(size: 10, color: TillStyle.faint)),
  ];
}
