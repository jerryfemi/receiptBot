import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/amount_in_words.dart';
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/market/market_header.dart';
import 'package:receipt_bot/documents/market/market_style.dart';

/// "AMOUNT IN WORDS" line under the table.
pw.Widget marketAmountInWords(DocumentData data, MarketStyle s) {
  return marketField(
    'AMOUNT IN WORDS',
    amountInWords(data.total, data.currencySymbol),
    s,
    size: 13,
  );
}

/// Notes and terms the business added, in small print.
List<pw.Widget> marketNotes(DocumentData data, MarketStyle s) {
  final notes = data.transaction.notes?.trim() ?? '';
  final terms = data.transaction.terms?.trim() ?? '';
  pw.Widget block(String label, String body) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: s.label(size: 9, bold: true)),
            pw.SizedBox(height: 3),
            pw.Text(body, style: s.text(size: 11, color: MarketStyle.muted)),
          ],
        ),
      );
  return [
    if (notes.isNotEmpty) block('NOTES', notes),
    if (terms.isNotEmpty) block('TERMS', terms),
  ];
}

/// Bank, account number and account name in three boxed columns (invoices).
pw.Widget marketBankBox(DocumentData data, MarketStyle s) {
  if (!data.isInvoice || !data.hasBankDetails) return pw.SizedBox();

  pw.Widget cell(String label, String value, pw.TextStyle style, {bool last = false}) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: last
              ? null
              : pw.BoxDecoration(
                  border: pw.Border(
                    right: pw.BorderSide(color: MarketStyle.rule, width: 1),
                  ),
                ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: s.label(size: 9, color: s.stamp, bold: true, spacing: 0.16)),
              pw.SizedBox(height: 3),
              pw.Text(value, style: style),
            ],
          ),
        ),
      );

  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14),
    child: pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: s.stamp, width: 1.5),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          cell('BANK', data.bankName!, s.text(medium: true)),
          cell('ACCOUNT NO.', data.accountNumber!, s.entry(size: 15, bold: true)),
          cell(
            'ACCOUNT NAME',
            data.accountName?.trim().isNotEmpty ?? false ? data.accountName! : data.name,
            s.text(size: 12, medium: true),
            last: true,
          ),
        ],
      ),
    ),
  );
}

/// The rubber stamp on the left and the signature line on the right.
pw.Widget marketStampAndSignature(DocumentData data, MarketStyle s) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 30),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, bottom: 6),
          child: data.isInvoice ? _dueStamp(data, s) : _paidStamp(data, s),
        ),
        _signature(data, s),
      ],
    ),
  );
}

pw.Widget _stamp(MarketStyle s, double degrees, double width, List<pw.Widget> lines) {
  return pw.Transform.rotate(
    angle: degrees * math.pi / 180,
    child: pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(3),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: s.stamp, width: 1),
      ),
      child: pw.Container(
        height: 86,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: s.stamp, width: 3),
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: lines,
        ),
      ),
    ),
  );
}

pw.Widget _paidStamp(DocumentData data, MarketStyle s) {
  return _stamp(s, 8, 176, [
    pw.Text(
      _short(data.name, 22).toUpperCase(),
      style: s.label(size: 9, color: s.stamp, bold: true, spacing: 0.16),
    ),
    pw.SizedBox(height: 2),
    pw.Text('PAID', style: s.display(size: 34, color: s.stamp, spacing: 0.12)),
    pw.SizedBox(height: 2),
    pw.Text(
      DateFormat('d MMM yyyy').format(data.date).toUpperCase(),
      style: s.entry(size: 11, color: s.stamp, bold: true),
    ),
  ]);
}

pw.Widget _dueStamp(DocumentData data, MarketStyle s) {
  final due = data.dueDate;
  final days = due == null
      ? null
      : DateTime(due.year, due.month, due.day)
          .difference(DateTime(data.date.year, data.date.month, data.date.day))
          .inDays;
  final detail = [
    if (days != null && days > 0) '$days ${days == 1 ? 'DAY' : 'DAYS'}',
    data.number,
  ].join(' · ');

  return _stamp(s, 6, 196, [
    pw.Text(
      due == null ? 'PAYMENT DUE' : 'PAYMENT DUE BY',
      style: s.label(size: 9, color: s.stamp, bold: true, spacing: 0.16),
    ),
    pw.SizedBox(height: 2),
    pw.Text(
      due == null
          ? 'ON RECEIPT'
          : DateFormat('d MMM yyyy').format(due).toUpperCase(),
      style: s.display(size: 28, color: s.stamp, spacing: 0.06),
    ),
    pw.SizedBox(height: 2),
    pw.Text(detail, style: s.entry(size: 11, color: s.stamp, bold: true)),
  ]);
}

pw.Widget _signature(DocumentData data, MarketStyle s) {
  final firstWord = data.name.split(RegExp(r'\s+')).first.toUpperCase();
  return pw.SizedBox(
    width: 160,
    child: pw.Column(
      children: [
        pw.Text(_short(data.name, 18), style: s.signature(), maxLines: 1),
        pw.Container(height: 1, color: MarketStyle.ink),
        pw.SizedBox(height: 4),
        pw.Text(
          data.isInvoice ? 'ISSUED BY' : 'SIGNED FOR ${_short(firstWord, 12)}',
          style: s.label(spacing: 0.14),
        ),
      ],
    ),
  );
}

String _short(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max - 1).trimRight()}…';
