import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/signature/signature_style.dart';

/// Monogram (or logo), business name, the script title and the
/// "prepared for" / number / date row.
pw.Widget signatureHeader(DocumentData data, SignatureStyle s) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Center(child: _monogram(data, s)),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          data.name.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: s.serifText(size: 17, medium: true, letterSpacing: 3.7),
        ),
      ),
      if (data.contactLine.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            data.contactLine.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: s.label(size: 9.5),
          ),
        ),
      ],
      pw.SizedBox(height: 20),
      _titleRow(data, s),
      pw.SizedBox(height: 20),
      _metaRow(data, s),
    ],
  );
}

pw.Widget _monogram(DocumentData data, SignatureStyle s) {
  final logo = data.logo;
  return pw.Container(
    width: 46,
    height: 46,
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      border: pw.Border.all(color: s.accent, width: 1),
    ),
    alignment: pw.Alignment.center,
    child: logo != null
        ? pw.ClipOval(
            child: pw.Image(logo, width: 40, height: 40, fit: pw.BoxFit.cover),
          )
        : pw.Text(
            data.initial,
            style: s.serifText(size: 24, italic: true, color: s.accent),
          ),
  );
}

pw.Widget _titleRow(DocumentData data, SignatureStyle s) {
  pw.Widget rule() =>
      pw.Expanded(child: pw.Container(height: 0.5, color: s.accent));
  pw.Widget diamond() => pw.Transform.rotate(
        angle: math.pi / 4,
        child: pw.Container(width: 5, height: 5, color: s.accent),
      );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      rule(),
      pw.SizedBox(width: 12),
      diamond(),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14),
        child: pw.Text(data.title, style: s.scriptText(50)),
      ),
      diamond(),
      pw.SizedBox(width: 12),
      rule(),
    ],
  );
}

pw.Widget _metaRow(DocumentData data, SignatureStyle s) {
  final customer = data.customerName;
  final due = data.dueDate;

  final right = data.isInvoice
      ? pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'No. ${data.number} · ISSUED '
              '${DocumentData.shortDate(data.date).toUpperCase()}',
              style: s.label(),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              due != null
                  ? 'Kindly pay by ${DocumentData.longDate(due)}'
                  : 'Payable on receipt',
              style: s.serifText(size: 14, italic: true),
            ),
          ],
        )
      : pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('No. ${data.number}', style: s.label()),
            pw.SizedBox(height: 4),
            pw.Text(
              DocumentData.longDate(data.date),
              style: s.serifText(size: 14, italic: true),
            ),
          ],
        );

  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      if (customer != null)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PREPARED FOR', style: s.label()),
            pw.SizedBox(height: 4),
            pw.Text(customer, style: s.serifText(size: 18)),
          ],
        )
      else
        pw.SizedBox(),
      right,
    ],
  );
}
