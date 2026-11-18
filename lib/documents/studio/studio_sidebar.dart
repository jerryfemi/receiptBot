import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/studio/studio_style.dart';

const double studioSidebarWidth = 228;

/// The full-height sidebar: who the business is, how to pay (invoices),
/// and the total in big type at the bottom. Drawn on every page.
pw.Widget studioSidebar(DocumentData data, StudioStyle s) {
  // Receipts sit on near-black; invoices on the accent colour.
  final fill = data.isInvoice ? s.accent : StudioStyle.ink;
  final tileFill = data.isInvoice ? StudioStyle.ink : s.accent;
  final soft = data.isInvoice ? PdfColor.fromHex('#D3D6FA') : StudioStyle.sideMuted;
  final softer = data.isInvoice ? PdfColor.fromHex('#EEF0FF') : StudioStyle.sideSoft;

  return pw.Container(
    width: studioSidebarWidth,
    color: fill,
    padding: const pw.EdgeInsets.fromLTRB(26, 34, 26, 28),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _logoTile(data, s, tileFill),
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

pw.Widget _logoTile(DocumentData data, StudioStyle s, PdfColor fill) {
  if (data.logo != null) {
    return pw.ClipRRect(
      horizontalRadius: 10,
      verticalRadius: 10,
      child: pw.Container(
        width: 40,
        height: 40,
        color: StudioStyle.white,
        child: pw.Image(data.logo!, fit: pw.BoxFit.cover),
      ),
    );
  }
  return pw.Container(
    width: 40,
    height: 40,
    alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(
      color: fill,
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
  if (!data.isInvoice) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: s.accent,
        borderRadius: pw.BorderRadius.circular(99),
      ),
      child: pw.Text('Paid', style: s.text(size: 11, color: StudioStyle.white, semiBold: true)),
    );
  }
  final due = data.dueDate;
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: StudioStyle.white, width: 1.5),
      borderRadius: pw.BorderRadius.circular(99),
    ),
    child: pw.Text(
      due == null ? 'Due on receipt' : 'Due ${DocumentData.shortDate(due)}',
      style: s.text(size: 11, color: StudioStyle.white, semiBold: true),
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
