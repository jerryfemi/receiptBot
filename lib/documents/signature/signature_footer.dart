import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/signature/signature_style.dart';

/// Receipts get a "PAID" seal; invoices get the "remit payment to" box.
pw.Widget signatureSettlement(DocumentData data, SignatureStyle s) {
  return data.isInvoice ? _paymentBox(data, s) : _paidSeal(data, s);
}

pw.Widget _paidSeal(DocumentData data, SignatureStyle s) {
  final seal = pw.Transform.rotate(
    angle: -10 * math.pi / 180,
    child: pw.Container(
      width: 92,
      height: 92,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: s.accent, width: 1.5),
      ),
      child: pw.Container(
        width: 80,
        height: 80,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          border: pw.Border.all(color: s.accent, width: 0.5),
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              _sealName(data.name),
              style: s.label(size: 7.5, color: s.accent),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'PAID',
              style: s.serifText(
                size: 17,
                medium: true,
                color: s.accent,
                letterSpacing: 1.7,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              DocumentData.romanDate(data.date),
              style: s.label(size: 7.5, color: s.accent),
            ),
          ],
        ),
      ),
    ),
  );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      seal,
      pw.SizedBox(width: 18),
      pw.Expanded(
        child: pw.Text(
          'Received with thanks.\nPlease keep this receipt for your records.',
          style: s.text(color: SignatureStyle.body),
        ),
      ),
    ],
  );
}

/// The seal's top line: the first word of the business name, kept short so
/// it fits inside the ring.
String _sealName(String name) {
  final first = name.split(RegExp(r'\s+')).first.toUpperCase();
  return first.length > 12 ? first.substring(0, 12) : first;
}

pw.Widget _paymentBox(DocumentData data, SignatureStyle s) {
  final due = data.dueDate;
  if (!data.hasBankDetails && due == null) return pw.SizedBox();

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: s.accent, width: 0.5),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (data.hasBankDetails)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('REMIT PAYMENT TO', style: s.label(color: s.accent)),
              pw.SizedBox(height: 5),
              pw.Text(data.bankName!, style: s.serifText(size: 16)),
              pw.SizedBox(height: 3),
              pw.Text(
                [data.accountNumber, data.accountName]
                    .where((v) => v != null && v.isNotEmpty)
                    .join(' · '),
                style: s.text(color: SignatureStyle.body),
              ),
            ],
          )
        else
          pw.SizedBox(),
        if (due != null)
          pw.Text(
            'Due\n${DocumentData.romanDate(due)}',
            textAlign: pw.TextAlign.right,
            style: s.serifText(size: 13, italic: true, color: s.accent),
          ),
      ],
    ),
  );
}

/// Notes and terms the business added to this sale, in small print.
List<pw.Widget> signatureNotes(DocumentData data, SignatureStyle s) {
  final notes = data.transaction.notes?.trim() ?? '';
  final terms = data.transaction.terms?.trim() ?? '';
  return [
    if (notes.isNotEmpty) ...[
      pw.Text('NOTES', style: s.label()),
      pw.SizedBox(height: 4),
      pw.Text(notes, style: s.text(size: 11, color: SignatureStyle.body)),
      pw.SizedBox(height: 10),
    ],
    if (terms.isNotEmpty) ...[
      pw.Text('TERMS', style: s.label()),
      pw.SizedBox(height: 4),
      pw.Text(terms, style: s.text(size: 10, color: SignatureStyle.muted)),
    ],
  ];
}

/// "with gratitude", on the last page only.
pw.Widget signatureSignOff(SignatureStyle s) {
  return pw.Text('with gratitude', style: s.scriptText(28));
}
