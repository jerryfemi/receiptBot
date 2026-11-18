import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/studio/studio_style.dart';

const double studioSidebarWidth = 228;

/// The full-height sidebar: who the business is, how to pay (invoices),
/// and the total in big type at the bottom. Drawn on every page.
pw.Widget studioSidebar(DocumentData data, StudioStyle s) {
  // The sidebar is the accent colour: blue on receipts, green on invoices.
  final fill = s.accent;
  final soft = _towardWhite(s.accent, 0.78);
  final softer = _towardWhite(s.accent, 0.9);

  return pw.Container(
    width: studioSidebarWidth,
    color: fill,
    padding: const pw.EdgeInsets.fromLTRB(26, 34, 26, 28),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _logo(data, s),
        pw.SizedBox(height: 18),
        pw.Text(
          data.name,
          style: s.headline(22, color: StudioStyle.white, bold: true, tracking: -0.01),
        ),
        if (_addressLines(data).isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            _addressLines(data).join('\n'),
            style: s.text(size: 11, color: soft, lineSpacing: 4),
          ),
        ],
        if (data.isInvoice && data.hasBankDetails) ...[
          pw.SizedBox(height: 30),
          _payToCard(data, s),
        ],
        pw.Spacer(),
        _statusPill(data, s),
        pw.SizedBox(height: 16),
        pw.Text(
          data.isInvoice ? 'Amount due' : 'Total paid',
          style: s.text(size: 11, color: soft),
        ),
        pw.SizedBox(height: 6),
        _bigTotal(data, s),
        pw.SizedBox(height: 6),
        pw.Text(
          '${data.currencySymbol}${NumberFormat('#,##0.00').format(data.total)}',
          style: s.text(color: softer),
        ),
      ],
    ),
  );
}

List<String> _addressLines(DocumentData data) => [
      ...?data.businessAddress
          ?.split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty),
      if (data.businessPhone?.trim().isNotEmpty ?? false) data.businessPhone!.trim(),
    ];

/// A colour mixed [amount] of the way toward white, for soft text on the
/// sidebar whatever the accent is.
PdfColor _towardWhite(PdfColor c, double amount) => PdfColor(
      c.red + (1 - c.red) * amount,
      c.green + (1 - c.green) * amount,
      c.blue + (1 - c.blue) * amount,
    );

/// The logo as it is, with no box behind it. Without a logo, the first
/// letter of the business name on a dark tile.
pw.Widget _logo(DocumentData data, StudioStyle s) {
  if (data.logo != null) {
    return pw.Container(
      height: 44,
      constraints: const pw.BoxConstraints(maxWidth: 150),
      alignment: pw.Alignment.centerLeft,
      child: pw.Image(data.logo!, fit: pw.BoxFit.contain),
    );
  }
  return pw.Container(
    width: 40,
    height: 40,
    alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(
      color: StudioStyle.ink,
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Text(data.initial, style: s.headline(20, color: StudioStyle.white, tracking: 0)),
  );
}

pw.Widget _payToCard(DocumentData data, StudioStyle s) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: StudioStyle.white,
      borderRadius: pw.BorderRadius.circular(12),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Pay to', style: s.text(size: 11, color: s.accent, semiBold: true)),
        pw.SizedBox(height: 4),
        pw.Text(data.accountNumber!, style: s.headline(21, tracking: 0.01)),
        pw.SizedBox(height: 4),
        pw.Text(data.bankName!, style: s.text(semiBold: true)),
        if (data.accountName?.trim().isNotEmpty ?? false) ...[
          pw.SizedBox(height: 3),
          pw.Text(data.accountName!, style: s.text(size: 11, color: StudioStyle.muted)),
        ],
      ],
    ),
  );
}

pw.Widget _statusPill(DocumentData data, StudioStyle s) {
  if (!data.isInvoice) return _paidBurst(s);

  final due = data.dueDate;
  // Radius is half the pill's height; anything bigger draws stray arcs.
  // The Row keeps the pill as wide as its text, not the whole sidebar.
  return pw.Row(children: [pw.Container(
    height: 20,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10),
    alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: StudioStyle.white, width: 1.5),
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Text(
      due == null ? 'Due on receipt' : 'Due ${DocumentData.shortDate(due)}',
      style: s.text(size: 11, color: StudioStyle.white, semiBold: true),
    ),
  )]);
}

/// A white starburst seal with PAID in the accent colour.
pw.Widget _paidBurst(StudioStyle s) {
  const size = 76.0;
  const points = 14;
  return pw.SizedBox(
    width: size,
    height: size,
    child: pw.Stack(
      alignment: pw.Alignment.center,
      children: [
        pw.CustomPaint(
          size: const PdfPoint(size, size),
          painter: (canvas, box) {
            final cx = box.x / 2;
            final cy = box.y / 2;
            const outer = size / 2;
            const inner = size / 2 * 0.74;
            canvas.setFillColor(StudioStyle.white);
            for (var i = 0; i < points * 2; i++) {
              final r = i.isEven ? outer : inner;
              final a = math.pi / 2 + i * math.pi / points;
              final x = cx + r * math.cos(a);
              final y = cy + r * math.sin(a);
              if (i == 0) {
                canvas.moveTo(x, y);
              } else {
                canvas.lineTo(x, y);
              }
            }
            canvas
              ..closePath()
              ..fillPath();
          },
        ),
        pw.Transform.rotate(
          angle: 12 * math.pi / 180,
          child: pw.Text('PAID', style: s.headline(17, color: s.accent, tracking: 0.02)),
        ),
      ],
    ),
  );
}

/// "₦1.8M" for big totals, the full amount for small ones, sized to fit.
pw.Widget _bigTotal(DocumentData data, StudioStyle s) {
  final text = data.total >= 100000
      ? '${data.currencySymbol}${NumberFormat.compact().format(data.total)}'
      : data.money(data.total);
  final size = text.length <= 6
      ? 44.0
      : text.length <= 8
          ? 36.0
          : 28.0;
  return pw.Text(
    text,
    style: s.headline(size, color: StudioStyle.white, tracking: -0.035),
    maxLines: 1,
  );
}
