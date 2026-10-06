import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/utils/country_utils.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/layouts/shared_components.dart';
import 'package:receipt_bot/layouts/design_tokens.dart';

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

  final uniqueIdString =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString();
  final uniqueId = uniqueIdString.length >= 5
      ? uniqueIdString.substring(uniqueIdString.length - 5)
      : uniqueIdString.padLeft(5, '0');

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

  final tableBorderColor = primary;
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
          pw.Text(
              "DATE: ${DateFormat('MMM dd, yyyy').format(transaction.date)}",
              style: styleBody.copyWith(color: PdfColors.grey700)),
          if (transaction.dueDate != null)
            pw.Text(
                "DUE DATE: ${DateFormat('MMM dd, yyyy').format(transaction.dueDate!)}",
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
                  style: styleLabel.copyWith(color: primary)),
              pw.SizedBox(height: 5),
              pw.Text(transaction.customerName.toUpperCase(),
                  style: styleBody.copyWith(font: serifFont)),
              if (transaction.customerAddress != null)
                pw.Text(transaction.customerAddress!,
                    style: styleBody.copyWith(
                        color: PdfColors.grey700, font: serifFont)),
              if (transaction.customerPhone != null)
                pw.Text(transaction.customerPhone!,
                    style: styleBody.copyWith(
                        color: PdfColors.grey700, font: serifFont)),
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

    SharedComponents.buildTransactionTable(
      transaction: transaction,
      currencySymbol: currencySymbol,
      headerStyle: styleLabel,
      bodyStyle: styleBody,
      tableBorder: tableBorder,
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      headerPadding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
        // Subtotal
        pw.TableRow(children: [
          pw.SizedBox(),
          pw.SizedBox(),
          cell("SUBTOTAL", align: pw.TextAlign.right, bold: true),
          cell(formatCurrency(transaction.subTotal, currencySymbol),
              align: pw.TextAlign.center, bold: true),
        ]),
        // Discount
        if (transaction.discount != null && transaction.discount! > 0)
          pw.TableRow(children: [
            pw.SizedBox(),
            pw.SizedBox(),
            cell("DISCOUNT", align: pw.TextAlign.right, bold: true),
            cell("-${formatCurrency(transaction.discount!, currencySymbol)}",
                align: pw.TextAlign.center, bold: true),
          ]),
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
    if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
      pw.SizedBox(height: 20),
      pw.Text("NOTES:", style: styleTitle.copyWith(fontSize: 12)),
      pw.SizedBox(height: 5),
      pw.Text(transaction.notes!, style: styleBody),
    ],
    if (transaction.terms != null && transaction.terms!.isNotEmpty) ...[
      pw.SizedBox(height: 20),
      pw.Text("TERMS & CONDITIONS:", style: styleTitle.copyWith(fontSize: 12)),
      pw.SizedBox(height: 5),
      pw.Text(transaction.terms!, style: styleBody.copyWith(fontSize: 8)),
    ],
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

  final uniqueIdString =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString();
  final uniqueId = uniqueIdString.length >= 5
      ? uniqueIdString.substring(uniqueIdString.length - 5)
      : uniqueIdString.padLeft(5, '0');

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
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('BILLED TO:',
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: accentColor)),
            pw.Text(transaction.customerName,
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
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
                    color: accentColor)),
            pw.SizedBox(height: 4),
            pw.Text(
                'Date: ${DateFormat('MMM dd, yyyy').format(transaction.date)}',
                style: const pw.TextStyle(fontSize: 10)),
            pw.Text('No: #R-$uniqueId',
                style: const pw.TextStyle(fontSize: 10)),
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
    SharedComponents.buildTransactionTable(
      transaction: transaction,
      currencySymbol: currencySymbol,
      headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: textColor),
      bodyStyle: const pw.TextStyle(fontSize: 10),
      tableBorder: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      headerPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    vertical: 2, horizontal: 10),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text('SUBTOTAL:   ',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(
                      formatCurrency(transaction.subTotal, currencySymbol),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (transaction.discount != null && transaction.discount! > 0)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 2, horizontal: 10),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text('DISCOUNT:   ',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text(
                        "-${formatCurrency(transaction.discount!, currencySymbol)}",
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.red),
                      ),
                    ],
                  ),
                ),
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

    if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
      pw.Text("NOTES:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 5),
      pw.Text(transaction.notes!, style: pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 10),
    ],
    if (transaction.terms != null && transaction.terms!.isNotEmpty) ...[
      pw.Text("TERMS & CONDITIONS:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 5),
      pw.Text(transaction.terms!, style: pw.TextStyle(fontSize: 8)),
      pw.SizedBox(height: 10),
    ],

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
