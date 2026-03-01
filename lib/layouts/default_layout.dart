import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/models/models.dart';

List<pw.Widget> defaultInvoiceLayout(
    pw.Context context,
    Transaction transaction,
    pw.MemoryImage? logoImage,
    PdfColor primary,
    PdfColor textColor,
    pw.Font regularFont,
    pw.Font boldFontParam,
    pw.Font? serifFont, // Added serifFont
    String? businessName,
    String? businessAddress,
    String? displayPhoneNumber,
    String? bankName,
    String? accountNumber,
    String? accountName,
    String currencySymbol) {
  // Fonts
  final headerFont = boldFontParam;
  final bodyFont = regularFont;
  final boldFont = boldFontParam;

  // Font Sizes
  const double fsTitle = 38; // "INVOICE"
  const double fsCompany = 24; // Company Name
  const double fsHeader = 10; // Table Headers / Section Titles
  const double fsBody = 10; // Normal Text

  final uniqueId =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString()
          .padLeft(5, '1')
          .substring(0, 5);

  // Styles
  final styleTitle = pw.TextStyle(
      font: headerFont,
      fontSize: fsTitle,
      color: primary,
      fontWeight: pw.FontWeight.bold);
  final styleCompany = pw.TextStyle(
      font: headerFont,
      fontSize: fsCompany,
      color: primary,
      fontWeight: pw.FontWeight.bold);
  final styleLabel = pw.TextStyle(
      font: boldFont,
      fontSize: fsHeader,
      color: textColor,
      fontWeight: pw.FontWeight.bold);
  final styleBody =
      pw.TextStyle(font: bodyFont, fontSize: fsBody, color: textColor);

  // Helper for table cells
  pw.Widget cell(String text,
      {pw.TextAlign align = pw.TextAlign.left,
      bool bold = false,
      bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: pw.Text(
        text,
        textAlign: align,
        style: isHeader
            ? styleLabel
            : (bold
                ? styleBody.copyWith(fontWeight: pw.FontWeight.bold)
                : styleBody),
      ),
    );
  }

  const tableBorderColor = PdfColors.grey400;
  final tableBorder = pw.TableBorder(
    left: pw.BorderSide(color: tableBorderColor),
    right: pw.BorderSide(color: tableBorderColor),
    top: pw.BorderSide(color: tableBorderColor),
    bottom: pw.BorderSide(color: tableBorderColor),
    horizontalInside: pw.BorderSide(color: tableBorderColor),
    verticalInside: pw.BorderSide(color: tableBorderColor),
  );

  return [
    // 1. Header Section
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("INVOICE", style: styleTitle),
          pw.SizedBox(width: 20), // Spacing buffer
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (logoImage != null) ...[
                  pw.ClipOval(
                    child: pw.Container(
                      height: 50,
                      width: 50,
                      color: PdfColors.white,
                      child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],
                pw.Text(businessName?.toUpperCase() ?? "BUSINESS NAME",
                    style: serifFont != null
                        ? pw.TextStyle(
                            font: serifFont,
                            fontSize: fsCompany,
                            color: primary,
                            fontWeight: pw.FontWeight.bold)
                        : styleCompany,
                    textAlign: pw.TextAlign.right),
                if (businessAddress != null && businessAddress.isNotEmpty) ...[
                  pw.SizedBox(height: 5),
                  pw.Text(businessAddress,
                      style: serifFont != null
                          ? pw.TextStyle(
                              font: serifFont,
                              fontSize: fsBody,
                              color: textColor)
                          : styleBody,
                      textAlign: pw.TextAlign.right),
                ],
                if (displayPhoneNumber != null &&
                    displayPhoneNumber.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(displayPhoneNumber,
                      style: serifFont != null
                          ? pw.TextStyle(
                              font: serifFont,
                              fontSize: fsBody,
                              color: textColor)
                          : styleBody,
                      textAlign: pw.TextAlign.right),
                ],
              ],
            ),
          )
        ]),

    pw.SizedBox(height: 25),

    // 2. Invoice Details (Left) & Space via Row
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text("INVOICE NUMBER: INV-$uniqueId",
              style: styleBody.copyWith(color: PdfColors.grey700)),
          pw.Text("DATE: ${DateFormat('MM.dd.yyyy').format(transaction.date)}",
              style: styleBody.copyWith(color: PdfColors.grey700)),
          if (transaction.dueDate != null)
            pw.Text(
                "DUE DATE: ${DateFormat('MM.dd.yyyy').format(transaction.dueDate!)}",
                style: styleBody.copyWith(color: PdfColors.grey700)),
        ]),
      ],
    ),

    pw.SizedBox(height: 25),

    // 3. Bill To & Payment Method
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Bill To (Left)
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Bill To:",
                  style: styleLabel.copyWith(color: PdfColors.grey700)),
              pw.SizedBox(height: 5),
              pw.Text(transaction.customerName.toUpperCase(), style: styleBody.copyWith(font: serifFont)),
              if (transaction.customerAddress != null)
                pw.Text(transaction.customerAddress!,
                    style: styleBody.copyWith(color: PdfColors.grey700,font: serifFont)),
              if (transaction.customerPhone != null)
                pw.Text(transaction.customerPhone!,
                    style: styleBody.copyWith(color: PdfColors.grey700,font: serifFont)),
            ],
          ),
        ),
        // Payment Method (Right)
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (bankName != null || transaction.bankName != null) ...[
                pw.Text("Payment Method",
                    style: styleLabel.copyWith(color: PdfColors.grey700)),
                pw.SizedBox(height: 5),
                pw.Text(bankName ?? transaction.bankName ?? '',
                    style: styleBody.copyWith(font: serifFont)),
                pw.Text(
                    (accountName ?? transaction.accountName ?? '')
                        .toUpperCase(),
                    style: styleBody.copyWith(font: serifFont)),
                pw.Text(accountNumber ?? transaction.accountNumber ?? '',
                    style: styleBody.copyWith(font: serifFont)),
              ]
            ],
          ),
        ),
      ],
    ),

    pw.SizedBox(height: 30),

    // 4. Items Table (Structured Grid)
    pw.Table(
      border: tableBorder,
      columnWidths: {
        0: const pw.FlexColumnWidth(3), // Description
        1: const pw.FlexColumnWidth(1), // Qty
        2: const pw.FlexColumnWidth(1.2), // Price
        3: const pw.FlexColumnWidth(1.2), // Subtotal
      },
      children: [
        // Header Row
        pw.TableRow(
          children: [
            cell("DESCRIPTION", isHeader: true), // Uppercase implied via input
            cell("QTY", isHeader: true, align: pw.TextAlign.center),
            cell("PRICE", isHeader: true, align: pw.TextAlign.center),
            cell("SUBTOTAL", isHeader: true, align: pw.TextAlign.center),
          ],
        ),
        // Check for empty rows helper
        ...transaction.items.map((item) {
          return pw.TableRow(
            children: [
              cell(item.description.toUpperCase()),
              cell(item.quantity.toString(), align: pw.TextAlign.center),
              cell(formatCurrency(item.amount, currencySymbol),
                  align: pw.TextAlign.center),
              cell(formatCurrency(item.amount * item.quantity, currencySymbol),
                  align: pw.TextAlign.center),
            ],
          );
        }),
      ],
    ),

    pw.Table(
      border: pw.TableBorder(
        left: pw.BorderSide(color: tableBorderColor),
        right: pw.BorderSide(color: tableBorderColor),
        bottom: pw.BorderSide(color: tableBorderColor),
        verticalInside: pw.BorderSide(color: tableBorderColor),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(3), // Spacer
        1: const pw.FlexColumnWidth(1), // Spacer
        2: const pw.FlexColumnWidth(1.2), // Label
        3: const pw.FlexColumnWidth(1.2), // Value
      },
      children: [
        // Tax
        if (transaction.tax != null && transaction.tax! > 0)
          pw.TableRow(children: [
            pw.SizedBox(),
            pw.SizedBox(),
            cell("TAX", align: pw.TextAlign.right, bold: true),
            cell(formatCurrency(transaction.tax!, currencySymbol),
                align: pw.TextAlign.center, bold: true),
          ]),
        // Grand Total
        pw.TableRow(children: [
          pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: transaction.amountInWords != null
                  ? pw.Text(transaction.amountInWords!,
                      style: styleBody.copyWith(
                          fontSize: 8, fontStyle: pw.FontStyle.italic))
                  : pw.SizedBox()),
          pw.SizedBox(),
          cell("GRAND TOTAL", align: pw.TextAlign.right, bold: true),
          cell(formatCurrency(transaction.transactionTotal, currencySymbol),
              align: pw.TextAlign.center, bold: true),
        ]),
      ],
    ),

    pw.SizedBox(height: 50),
  ];
}

List<pw.Widget> defaultReceiptLayout(
    pw.Context context,
    Transaction transaction,
    pw.MemoryImage? logoImage,
    PdfColor primary,
    PdfColor textColor,
    pw.Font regularFont,
    pw.Font boldFont,
    pw.Font? serifFont,
    String? businessName,
    String? businessAddress,
    String? displayPhoneNumber,
    String currencySymbol) {
  final accentColor = primary; // Use primary color for accent
  const secondaryColor = PdfColors.grey600;

  final uniqueId =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString()
          .padLeft(5, '1')
          .substring(0, 5);

  return [
    // --- HEADER (Left-Aligned Text, Right-Aligned Logo) ---
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left Side: Text Details (Expanded to prevent overflowing into logo)
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                businessName?.toUpperCase() ?? 'BUSINESS NAME',
                style: serifFont != null
                    ? pw.TextStyle(
                        font: serifFont,
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: accentColor,
                      )
                    : pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: accentColor,
                      ),
              ),
              if (businessAddress != null && businessAddress.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  businessAddress,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
              if (displayPhoneNumber != null &&
                  displayPhoneNumber.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  displayPhoneNumber,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ],
          ),
        ),

        pw.SizedBox(width: 20), // Spacing between text and logo

        // Right Side: Logo
        if (logoImage != null)
          pw.ClipOval(
            child: pw.Container(
              height: 80,
              width: 80,
              color: PdfColors.white, // Ensure white background to be safe
              child: pw.Image(logoImage, fit: pw.BoxFit.cover),
            ),
          ),
      ],
    ),

    pw.SizedBox(height: 20),

    // --- TRANSACTIONS  ---
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('BILLED TO:',
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: secondaryColor)),
        pw.Text(transaction.customerName,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        if (transaction.customerAddress != null)
          pw.Text(transaction.customerAddress!,
              style: const pw.TextStyle(fontSize: 10)),
        if (transaction.customerPhone != null)
          pw.Text(transaction.customerPhone!,
              style: const pw.TextStyle(fontSize: 10)),
      ]),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('RECEIPT INFO:',
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: secondaryColor)),
        pw.SizedBox(height: 4),
        pw.Text('Date: ${DateFormat('MM.dd.yyyy').format(transaction.date)}',
            style: const pw.TextStyle(fontSize: 10)),
        pw.Text('No: #R-$uniqueId', style: const pw.TextStyle(fontSize: 10)),
      ]),
    ]),

    pw.SizedBox(height: 10),
    pw.Center(
      child: pw.Text(
        'RECEIPT',
        style: pw.TextStyle(
          color: secondaryColor,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),

    // --- ITEMS TABLE ---
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3), // Item
        1: const pw.FlexColumnWidth(1), // Qty
        2: const pw.FlexColumnWidth(1.5), // Price
        3: const pw.FlexColumnWidth(1.5), // Total
      },
      children: [
        // Header
        pw.TableRow(
          children: [
            _tableHeader('DESCRIPTION', color: textColor),
            _tableHeader('QTY',
                alignment: pw.TextAlign.center, color: textColor),
            _tableHeader('PRICE',
                alignment: pw.TextAlign.right, color: textColor),
            _tableHeader('TOTAL',
                alignment: pw.TextAlign.right, color: textColor),
          ],
        ),
        // Items
        ...transaction.items.map((item) {
          return pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
            ),
            children: [
              _tableCell(item.description),
              _tableCell(item.quantity.toString(),
                  alignment: pw.TextAlign.center),
              _tableCell(formatCurrency(item.amount, currencySymbol),
                  alignment: pw.TextAlign.right),
              _tableCell(
                  formatCurrency(item.amount * item.quantity, currencySymbol),
                  alignment: pw.TextAlign.right),
            ],
          );
        }),
      ],
    ),

    pw.SizedBox(height: 15),

    // --- TOTALS ---
    pw.Row(
      children: [
        pw.Spacer(), // Push to right
        pw.Container(
          width: 250, // Constraint width to force wrapping
          padding: const pw.EdgeInsets.only(right: 20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (transaction.tax != null && transaction.tax! > 0)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 2, horizontal: 10),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text('TAX:   ',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text(
                        formatCurrency(transaction.tax!, currencySymbol),
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('TOTAL AMOUNT:   ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    formatCurrency(
                        transaction.transactionTotal, currencySymbol),
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              if (transaction.amountInWords != null)
                pw.Text(
                  '(${transaction.amountInWords})',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: 10, fontStyle: pw.FontStyle.italic),
                ),
            ],
          ),
        ),
      ],
    ),

    pw.SizedBox(height: 30), // Spacer replacement

    // --- FOOTER ---
    pw.Divider(color: PdfColors.grey300),
    pw.SizedBox(height: 10),
    pw.SizedBox(height: 5),
    pw.Center(
      child: pw.Text(
        'Thank you for your patronage!',
        style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            fontStyle: pw.FontStyle.italic,
            color: secondaryColor),
      ),
    ),
    pw.SizedBox(height: 5),
  ];
}

pw.Widget _tableHeader(String text,
    {pw.TextAlign alignment = pw.TextAlign.left, PdfColor? color}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    child: pw.Text(
      text,
      textAlign: alignment,
      style: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
        color: color ?? PdfColors.grey700,
      ),
    ),
  );
}

pw.Widget _tableCell(String text,
    {pw.TextAlign alignment = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    child: pw.Text(
      text,
      textAlign: alignment,
      style: const pw.TextStyle(fontSize: 10),
    ),
  );
}
