import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/till/till_style.dart';

/// The torn, saw-tooth edge at the top or bottom of the slip.
pw.Widget tillTeeth({required double width, required bool top}) {
  const tooth = 10.0;
  return pw.CustomPaint(
    size: PdfPoint(width, tooth),
    painter: (canvas, size) {
      canvas.setFillColor(TillStyle.paper);
      // PDF y runs upwards: y = 0 is the bottom of this strip.
      for (var x = 0.0; x + tooth <= size.x + 0.01; x += tooth) {
        if (top) {
          canvas
            ..moveTo(x, 0)
            ..lineTo(x + tooth / 2, tooth)
            ..lineTo(x + tooth, 0);
        } else {
          canvas
            ..moveTo(x, tooth)
            ..lineTo(x + tooth / 2, 0)
            ..lineTo(x + tooth, tooth);
        }
        canvas.closePath();
      }
      canvas.fillPath();
    },
  );
}

/// A dashed tear line, with space above and below.
pw.Widget tillDash({double above = 10, double below = 10}) => pw.Container(
      margin: pw.EdgeInsets.only(top: above, bottom: below),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: TillStyle.ink,
            width: 1.5,
            style: pw.BorderStyle.dashed,
          ),
        ),
      ),
    );

/// The double rule above the total.
pw.Widget tillDouble() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(height: 0.9, color: TillStyle.ink),
          pw.SizedBox(height: 1.2),
          pw.Container(height: 0.9, color: TillStyle.ink),
        ],
      ),
    );

/// Text on the left, text on the right, one line.
pw.Widget tillLine(
  String left,
  String right, {
  required pw.TextStyle style,
  pw.TextStyle? rightStyle,
  pw.CrossAxisAlignment align = pw.CrossAxisAlignment.end,
}) =>
    pw.Row(
      crossAxisAlignment: align,
      children: [
        pw.Expanded(child: pw.Text(left, style: style)),
        pw.SizedBox(width: 8),
        pw.Text(right, style: rightStyle ?? style),
      ],
    );
