import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/layouts/design_tokens.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/utils/country_utils.dart';

class SharedComponents {
  /// Builds the 'Billed To' section (Customer details)
  static pw.Widget buildBilledToSection({
    required Transaction transaction,
    required pw.TextStyle labelStyle,
    required pw.TextStyle bodyStyle,
    required pw.TextStyle nameStyle,
    String label = "BILLED TO:",
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: labelStyle),
        pw.SizedBox(height: AppSpacing.xs),
        pw.Text(transaction.customerName, style: nameStyle),
        if (transaction.customerAddress != null &&
            transaction.customerAddress!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(transaction.customerAddress!, style: bodyStyle),
        ],
        if (transaction.customerPhone != null &&
            transaction.customerPhone!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(transaction.customerPhone!, style: bodyStyle),
        ],
      ],
    );
  }

  /// Builds the metadata section (Invoice No, Date, Due Date)
  static pw.Widget buildInvoiceMetadata({
    required Transaction transaction,
    required pw.TextStyle labelStyle,
    required pw.TextStyle valueStyle,
    String prefix = "INV-",
    String titleLabel = "INVOICE NO:",
    String dateLabel = "DATE:",
    String dueDateLabel = "DUE DATE:",
    bool rightAlign = true,
  }) {
    final uniqueIdString =
        (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
            .abs()
            .toString();
    final uniqueId = uniqueIdString.length >= 5
        ? uniqueIdString.substring(uniqueIdString.length - 5)
        : uniqueIdString.padLeft(5, '0');

    pw.Widget _buildRow(String label, String value) {
      return pw.Row(
        mainAxisAlignment:
            rightAlign ? pw.MainAxisAlignment.end : pw.MainAxisAlignment.start,
        children: [
          pw.Text(label, style: labelStyle),
          pw.SizedBox(width: AppSpacing.sm),
          pw.Text(value, style: valueStyle),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment:
          rightAlign ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      children: [
        _buildRow(titleLabel, "$prefix$uniqueId"),
        pw.SizedBox(height: AppSpacing.xs),
        _buildRow(
            dateLabel, DateFormat('MMM dd, yyyy').format(transaction.date)),
        if (transaction.dueDate != null) ...[
          pw.SizedBox(height: AppSpacing.xs),
          _buildRow(dueDateLabel,
              DateFormat('MMM dd, yyyy').format(transaction.dueDate!)),
        ],
      ],
    );
  }

  /// Helper for table cell rendering
  static pw.Widget _tableCell(String text,
      {pw.TextAlign alignment = pw.TextAlign.left,
      required pw.TextStyle style,
      pw.EdgeInsets? padding}) {
    return pw.Padding(
      padding: padding ?? const pw.EdgeInsets.symmetric(
          vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
      child: pw.Text(text, textAlign: alignment, style: style),
    );
  }

  /// Builds the standardized transaction table
  static pw.Widget buildTransactionTable({
    required Transaction transaction,
    required String currencySymbol,
    required pw.TextStyle headerStyle,
    required pw.TextStyle bodyStyle,
    pw.TableBorder? tableBorder,
    pw.BoxDecoration? headerDecoration,
    Map<int, pw.TableColumnWidth>? columnWidths,
    pw.EdgeInsets? cellPadding,
    pw.EdgeInsets? headerPadding,
  }) {
    final widths = columnWidths ??
        {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1.2),
        };

    return pw.Table(
      border: tableBorder ??
          pw.TableBorder.all(color: AppColors.defaultTableBorder, width: 0.5),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: headerDecoration,
          children: [
            _tableCell("ITEM DESCRIPTION",
                alignment: pw.TextAlign.left, style: headerStyle, padding: headerPadding),
            _tableCell("PRICE",
                alignment: pw.TextAlign.center, style: headerStyle, padding: headerPadding),
            _tableCell("QTY",
                alignment: pw.TextAlign.center, style: headerStyle, padding: headerPadding),
            _tableCell("TOTAL",
                alignment: pw.TextAlign.right, style: headerStyle, padding: headerPadding),
          ],
        ),
        ...transaction.items.map((item) {
          return pw.TableRow(
            children: [
              _tableCell(item.description,
                  alignment: pw.TextAlign.left, style: bodyStyle, padding: cellPadding),
              _tableCell(formatCurrency(item.amount, currencySymbol),
                  alignment: pw.TextAlign.center, style: bodyStyle, padding: cellPadding),
              _tableCell(item.quantity.toString(),
                  alignment: pw.TextAlign.center, style: bodyStyle, padding: cellPadding),
              _tableCell(
                  formatCurrency(item.amount * item.quantity, currencySymbol),
                  alignment: pw.TextAlign.right,
                  style: bodyStyle, padding: cellPadding),
            ],
          );
        }),
      ],
    );
  }

  /// Builds the standard subtotal, discount, tax, and total section
  static pw.Widget buildTotalsBox({
    required Transaction transaction,
    required String currencySymbol,
    required pw.TextStyle labelStyle,
    required pw.TextStyle valueStyle,
    required pw.TextStyle grandTotalLabelStyle,
    required pw.TextStyle grandTotalValueStyle,
    pw.TableBorder? tableBorder,
  }) {
    pw.TableRow _row(String label, String value, {bool isGrandTotal = false}) {
      return pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(AppSpacing.sm),
            child: pw.Text(label,
                style: isGrandTotal ? grandTotalLabelStyle : labelStyle,
                textAlign: pw.TextAlign.left),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(AppSpacing.sm),
            child: pw.Text(value,
                style: isGrandTotal ? grandTotalValueStyle : valueStyle,
                textAlign: pw.TextAlign.right),
          ),
        ],
      );
    }

    return pw.Container(
      width: 250,
      child: pw.Table(
        border: tableBorder ??
            pw.TableBorder.all(color: AppColors.defaultTableBorder, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1),
          1: const pw.FlexColumnWidth(1),
        },
        children: [
          _row("Sub Total",
              formatCurrency(transaction.subTotal, currencySymbol)),
          if (transaction.discount != null && transaction.discount! > 0)
            _row("Discount",
                "-${formatCurrency(transaction.discount!, currencySymbol)}"),
          if (transaction.tax != null && transaction.tax! > 0)
            _row("Tax", formatCurrency(transaction.tax!, currencySymbol)),
          _row("Total Amount",
              formatCurrency(transaction.transactionTotal, currencySymbol),
              isGrandTotal: true),
        ],
      ),
    );
  }
}
