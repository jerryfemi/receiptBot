import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/models.dart';

class PdfService {
  Future<Uint8List> generateReceipt(
    BusinessProfile profile,
    Transaction transaction, {
    int themeIndex = 0, // 0: B&W, 1: Beige, 2: Blue
    Organization? org, // Optional Organization context
  }) async {
    // Load Fonts
    final regularFontData =
        await File('public/fonts/Roboto-VariableFont_wdth,wght.ttf')
            .readAsBytes();
    final regularFont = pw.Font.ttf(regularFontData.buffer.asByteData());

    final boldFontData =
        await File('public/fonts/Roboto-VariableFont_wdth,wght.ttf')
            .readAsBytes();
    final boldFont = pw.Font.ttf(boldFontData.buffer.asByteData());

    final pdf = pw.Document();

    // Determine values correctly from org or fallback
    final usedLogoUrl = org?.logoUrl ?? profile.logoUrl;
    final usedBusinessName = org?.businessName ?? profile.businessName;
    final usedBusinessAddress = org?.businessAddress ?? profile.businessAddress;
    final usedDisplayPhoneNumber =
        org?.displayPhoneNumber ?? profile.displayPhoneNumber;
    final usedBankName = org?.bankName ?? profile.bankName;
    final usedAccountNumber = org?.accountNumber ?? profile.accountNumber;
    final usedAccountName = org?.accountName ?? profile.accountName;

    // 1. Load Logo
    pw.MemoryImage? logoImage;
    if (usedLogoUrl != null) {
      try {
        final response = await http
            .get(Uri.parse(usedLogoUrl))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          logoImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        print('Error loading logo: $e');
      }
    }

    // Define Theme Colors
    PdfColor bg;
    PdfColor primary;
    const textColor = PdfColors.black;

    switch (themeIndex) {
      case 1: // Beige
        bg = PdfColor.fromHex('#EFE9DB');
        primary = PdfColor.fromHex('#D73138');
        break;
      case 2: // Blue
        bg = PdfColor.fromHex('#E3F2FD'); // Light Blue
        primary = PdfColor.fromHex('#1565C0'); // Dark Blue
        break;
      case 0: // B&W (Default)
      default:
        bg = PdfColors.white;
        primary = PdfColors.black;
        break;
    }

    // Use MultiPage to support PageTheme properly
    pdf.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20), // Smaller margin for A5
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: bg),
        ),
      ),
      build: (context) => [
        if (transaction.type == TransactionType.invoice)
          ..._generateInvoiceLayout(
              context,
              transaction,
              logoImage,
              primary,
              textColor,
              regularFont,
              boldFont,
              usedBusinessName,
              usedBusinessAddress,
              usedDisplayPhoneNumber,
              usedBankName,
              usedAccountNumber,
              usedAccountName,
              org?.currencySymbol ?? profile.currencySymbol)
        else
          ..._generateReceiptLayout(
              context,
              transaction,
              logoImage,
              primary,
              textColor,
              regularFont,
              boldFont,
              usedBusinessName,
              usedBusinessAddress,
              usedDisplayPhoneNumber,
              org?.currencySymbol ?? profile.currencySymbol)
      ],
    ));

    return pdf.save();
  }

  // --- CORPORATE INVOICE LAYOUT ---
  List<pw.Widget> _generateInvoiceLayout(
      pw.Context context,
      Transaction transaction,
      pw.MemoryImage? logoImage,
      PdfColor primary,
      PdfColor textColor,
      pw.Font regularFont,
      pw.Font boldFontParam,
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
    const double fsCompany = 18; // Company Name
    const double fsHeader = 10; // Table Headers / Section Titles
    const double fsBody = 10; // Normal Text

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
                      style: styleCompany, textAlign: pw.TextAlign.right),
                  pw.SizedBox(height: 5),
                  pw.Text(businessAddress ?? "",
                      style: styleBody, textAlign: pw.TextAlign.right),
                  pw.Text(displayPhoneNumber ?? "",
                      style: styleBody, textAlign: pw.TextAlign.right),
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
            pw.Text(
                "INVOICE NUMBER: #${transaction.date.millisecondsSinceEpoch.toString().substring(8)}",
                style: styleBody.copyWith(color: PdfColors.grey700)),
            pw.Text("DATE: ${DateFormat.yMMMMd().format(transaction.date)}",
                style: styleBody.copyWith(color: PdfColors.grey700)),
            if (transaction.dueDate != null)
              pw.Text(
                  "DUE DATE: ${DateFormat.yMMMMd().format(transaction.dueDate!)}",
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
                pw.Text(transaction.customerName.toUpperCase(),
                    style: styleBody),
                if (transaction.customerAddress != null)
                  pw.Text(transaction.customerAddress!,
                      style: styleBody.copyWith(color: PdfColors.grey700)),
                if (transaction.customerPhone != null)
                  pw.Text(transaction.customerPhone!,
                      style: styleBody.copyWith(color: PdfColors.grey700)),
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
                      style: styleBody),
                  pw.Text(
                      (accountName ?? transaction.accountName ?? '')
                          .toUpperCase(),
                      style: styleBody),
                  pw.Text(accountNumber ?? transaction.accountNumber ?? '',
                      style: styleBody),
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
              cell("DESCRIPTION",
                  isHeader: true), // Uppercase implied via input
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
                cell(_formatCurrency(item.amount, currencySymbol),
                    align: pw.TextAlign.center),
                cell(
                    _formatCurrency(
                        item.amount * item.quantity, currencySymbol),
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
          // Subtotal (Optional if same as total)
          // Tax
          if (transaction.tax != null && transaction.tax! > 0)
            pw.TableRow(children: [
              pw.SizedBox(),
              pw.SizedBox(),
              cell("TAX", align: pw.TextAlign.right, bold: true),
              cell(_formatCurrency(transaction.tax!, currencySymbol),
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
            cell(_formatCurrency(transaction.transactionTotal, currencySymbol),
                align: pw.TextAlign.center, bold: true),
          ]),
        ],
      ),

      pw.SizedBox(height: 50),
    ];
  }

// GENERATE RECEIPT
  List<pw.Widget> _generateReceiptLayout(
      pw.Context context,
      Transaction transaction,
      pw.MemoryImage? logoImage,
      PdfColor primary,
      PdfColor textColor,
      pw.Font regularFont,
      pw.Font boldFont,
      String? businessName,
      String? businessAddress,
      String? displayPhoneNumber,
      String currencySymbol) {
    final accentColor = primary; // Use primary color for accent
    const secondaryColor = PdfColors.grey600;

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
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: accentColor,
                  ),
                ),
                pw.SizedBox(height: 5),
                if (businessAddress != null && businessAddress.isNotEmpty) ...[
                  pw.Text(
                    businessAddress,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
                if (displayPhoneNumber != null &&
                    displayPhoneNumber.isNotEmpty) ...[
                  pw.Text(
                    displayPhoneNumber,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
                pw.SizedBox(height: 10),
                pw.Text(
                  'RECEIPT',
                  style: pw.TextStyle(
                    color: accentColor,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(width: 20), // Spacing between text and logo

          // Right Side: Logo
          if (logoImage != null)
            pw.ClipOval(
              child: pw.Container(
                height: 60,
                width: 60,
                color: PdfColors.white, // Ensure white background to be safe
                child: pw.Image(logoImage, fit: pw.BoxFit.cover),
              ),
            ),
        ],
      ),

      pw.SizedBox(height: 20),

      // --- TRANSACTIONS  ---
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('BILL TO:',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: secondaryColor)),
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
                  color: secondaryColor)),
          pw.Text('Date: ${DateFormat.yMMMMd().format(transaction.date)}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
              'No: #${transaction.date.millisecondsSinceEpoch.toString().substring(6)}',
              style: const pw.TextStyle(fontSize: 10)),
        ]),
      ]),

      pw.SizedBox(height: 10),

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
              _tableHeader('DESCRIPTION', color: PdfColors.black),
              _tableHeader('QTY',
                  alignment: pw.TextAlign.center, color: PdfColors.black),
              _tableHeader('PRICE',
                  alignment: pw.TextAlign.right, color: PdfColors.black),
              _tableHeader('TOTAL',
                  alignment: pw.TextAlign.right, color: PdfColors.black),
            ],
          ),
          // Items
          ...transaction.items.map((item) {
            return pw.TableRow(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom:
                        pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
              ),
              children: [
                _tableCell(item.description),
                _tableCell(item.quantity.toString(),
                    alignment: pw.TextAlign.center),
                _tableCell(_formatCurrency(item.amount, currencySymbol),
                    alignment: pw.TextAlign.right),
                _tableCell(
                    _formatCurrency(
                        item.amount * item.quantity, currencySymbol),
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
                          _formatCurrency(transaction.tax!, currencySymbol),
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
                      _formatCurrency(
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

  String _formatCurrency(double amount, String symbol) {
    // Basic comma formatting
    return '$symbol${amount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
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
}

extension TransactionTotal on Transaction {
  double get transactionTotal {
    final double subtotal =
        items.fold(0, (sum, item) => sum + (item.amount * item.quantity));
    return subtotal + (tax ?? 0);
  }
}
