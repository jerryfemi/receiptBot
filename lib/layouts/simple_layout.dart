import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/models/models.dart';

List<pw.Widget> simpleInvoice(
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
    String? bankName,
    String? accountNumber,
    String? accountName,
    String currencySymbol) {
  final styleLabel =
      pw.TextStyle(font: boldFont, fontSize: 10, color: textColor);
  final styleBody =
      pw.TextStyle(font: regularFont, fontSize: 10, color: textColor);
  final styleTitle =
      pw.TextStyle(font: boldFont, fontSize: 32, color: PdfColors.black);

  final uniqueId =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString()
          .padLeft(5, '1')
          .substring(0, 5);

  return [
    // HEADER: "INVOICE" Top Left, Meta top right (in a box)
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("INVOICE", style: styleTitle),
          pw.Container(
              width: 150,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 1)),
              child: pw.Column(children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text("INVOICE NO.", style: styleLabel),
                          pw.Text("INV-$uniqueId", style: styleBody),
                        ])),
                pw.Divider(color: PdfColors.black, thickness: 1, height: 1),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text("DATE", style: styleLabel),
                          pw.Text(
                              DateFormat('MM.dd.yyyy').format(transaction.date),
                              style: styleBody),
                        ])),
              ]))
        ]),
    pw.SizedBox(height: 30),

    // ADDRESSES: FROM and BILLED TO underneath (split screen)
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // FROM
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text("FROM :", style: styleTitle.copyWith(fontSize: 14)),
                pw.SizedBox(height: 10),
                pw.Text(businessName?.toUpperCase() ?? "BUSINESS NAME",
                    style: serifFont != null
                        ? pw.TextStyle(
                            font: serifFont, fontSize: 14, color: textColor)
                        : styleBody),
                pw.SizedBox(height: 5),
                if (businessAddress != null && businessAddress.isNotEmpty) ...[
                  pw.Text(businessAddress,
                      style: serifFont != null
                          ? pw.TextStyle(
                              font: serifFont, fontSize: 10, color: textColor)
                          : styleBody),
                ],
                pw.SizedBox(height: 5),
                if (displayPhoneNumber != null &&
                    displayPhoneNumber.isNotEmpty) ...[
                  pw.Text(displayPhoneNumber,
                      style: serifFont != null
                          ? pw.TextStyle(
                              font: serifFont, fontSize: 10, color: textColor)
                          : styleBody),
                ]
              ])),
          pw.SizedBox(width: 20),
          // BILLED TO
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text("BILLED TO :",
                    style: styleTitle.copyWith(fontSize: 14)),
                pw.SizedBox(height: 10),
                pw.Text(transaction.customerName.toUpperCase(),
                    style: styleBody),
                pw.SizedBox(height: 5),
                if (transaction.customerAddress != null &&
                    transaction.customerAddress!.isNotEmpty) ...[
                  pw.Text(transaction.customerAddress ?? "", style: styleBody),
                ],
                pw.SizedBox(height: 5),
                if (transaction.customerPhone != null &&
                    transaction.customerPhone!.isNotEmpty) ...[
                  pw.Text(transaction.customerPhone ?? "", style: styleBody),
                ]
              ]))
        ]),
    pw.SizedBox(height: 30),

    pw.Text("ITEMS",
        style: styleTitle.copyWith(fontSize: 16, color: PdfColors.grey700)),
    pw.SizedBox(height: 10),

    // TABLE: STRICT GRIDS
    pw.Table(
        border: const pw.TableBorder(
          top: pw.BorderSide(color: PdfColors.black, width: 1),
          bottom: pw.BorderSide(color: PdfColors.black, width: 1),
          left: pw.BorderSide(color: PdfColors.black, width: 1),
          right: pw.BorderSide(color: PdfColors.black, width: 1),
          verticalInside: pw.BorderSide(color: PdfColors.black, width: 1),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1.2),
          3: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(
              decoration: const pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black, width: 1))),
              children: [
                _tableHeader('Description',
                    alignment: pw.TextAlign.center, color: PdfColors.black),
                _tableHeader('Qty.',
                    alignment: pw.TextAlign.center, color: PdfColors.black),
                _tableHeader('Unit Price',
                    alignment: pw.TextAlign.center, color: PdfColors.black),
                _tableHeader('Amount',
                    alignment: pw.TextAlign.center, color: PdfColors.black),
              ]),
          ...transaction.items.map((item) {
            return pw.TableRow(children: [
              _tableCell(item.description, alignment: pw.TextAlign.left),
              _tableCell(item.quantity.toString(),
                  alignment: pw.TextAlign.center),
              _tableCell(formatCurrency(item.amount, currencySymbol),
                  alignment: pw.TextAlign.center),
              _tableCell(
                  formatCurrency(item.amount * item.quantity, currencySymbol),
                  alignment: pw.TextAlign.center),
            ]);
          }),
        ]),

    // FOOTER TOTAL BOX (Bottom Right strict grid)
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
      pw.Container(
          width: 200,
          child: pw.Table(
              border: pw.TableBorder(
                left: const pw.BorderSide(color: PdfColors.black, width: 1),
                right: const pw.BorderSide(color: PdfColors.black, width: 1),
                bottom: const pw.BorderSide(color: PdfColors.black, width: 1),
                verticalInside:
                    const pw.BorderSide(color: PdfColors.black, width: 1),
                horizontalInside:
                    const pw.BorderSide(color: PdfColors.black, width: 1),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(children: [
                  _tableHeader('Sub Total',
                      alignment: pw.TextAlign.center, color: PdfColors.black),
                  _tableCell(
                      formatCurrency(
                          transaction.transactionTotal - (transaction.tax ?? 0),
                          currencySymbol),
                      alignment: pw.TextAlign.right),
                ]),
                pw.TableRow(children: [
                  _tableHeader('Tax',
                      alignment: pw.TextAlign.center, color: PdfColors.black),
                  _tableCell(
                      formatCurrency(transaction.tax ?? 0, currencySymbol),
                      alignment: pw.TextAlign.right),
                ]),
                pw.TableRow(children: [
                  _tableHeader('Total Amount',
                      alignment: pw.TextAlign.center, color: PdfColors.black),
                  _tableCell(
                      formatCurrency(
                          transaction.transactionTotal, currencySymbol),
                      alignment: pw.TextAlign.right),
                ]),
              ]))
    ]),

    pw.SizedBox(height: 30),

    // PAYMENT DETAILS (Bottom Left)
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text("PAYMENT METHOD:", style: styleTitle.copyWith(fontSize: 14)),
      pw.SizedBox(height: 10),
      if (bankName != null || transaction.bankName != null) ...[
        pw.Text("Bank Name: ${bankName ?? transaction.bankName}",
            style: styleBody),
        pw.SizedBox(height: 3),
        pw.Text("Account Name: ${accountName ?? transaction.accountName}",
            style: styleBody),
        pw.SizedBox(height: 3),
        pw.Text("Account No: ${accountNumber ?? transaction.accountNumber}",
            style: styleBody),
      ]
    ]),
  ];
}

List<pw.Widget> simpleReceipt(
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
  final styleLabel =
      pw.TextStyle(font: boldFont, fontSize: 10, color: textColor);
  final styleBody =
      pw.TextStyle(font: regularFont, fontSize: 10, color: textColor);
  final styleTitle =
      pw.TextStyle(font: boldFont, fontSize: 32, color: PdfColors.black);

  final uniqueId =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString()
          .padLeft(5, '1')
          .substring(0, 5);

  return [
    //  RECEIPT HEADER
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: Logo + Business Details
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.ClipOval(
                  child: pw.Container(
                    height: 80,
                    width: 80,
                    color: PdfColors.white,
                    child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                  ),
                ),
                pw.SizedBox(width: 15),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      businessName?.toUpperCase() ?? "BUSINESS NAME",
                      style: serifFont != null
                          ? pw.TextStyle(
                              font: serifFont, fontSize: 32, color: primary)
                          : styleTitle.copyWith(fontSize: 24),
                    ),
                    if (businessAddress != null &&
                        businessAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(businessAddress,
                          style: serifFont != null
                              ? pw.TextStyle(
                                  font: serifFont,
                                  fontSize: 10,
                                  color: textColor)
                              : styleBody),
                    ],
                    if (displayPhoneNumber != null &&
                        displayPhoneNumber.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(displayPhoneNumber,
                          style: serifFont != null
                              ? pw.TextStyle(
                                  font: serifFont,
                                  fontSize: 10,
                                  color: textColor)
                              : styleBody),
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 20),
        // Right: Receipt Meta
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text("RECEIPT NO: ",
                    style: styleLabel.copyWith(color: PdfColors.black)),
                pw.Text("R-$uniqueId", style: styleBody),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text("date: ",
                    style: styleLabel.copyWith(color: PdfColors.black)),
                pw.Text(DateFormat('MM.dd.yyyy').format(transaction.date),
                    style: styleBody),
              ],
            ),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 30),

    // BILLED TO Section
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text("BILLED TO :", style: styleTitle.copyWith(fontSize: 14)),
      pw.SizedBox(height: 10),
      pw.Text(transaction.customerName.toUpperCase(), style: styleBody),
      pw.SizedBox(height: 5),
      if (transaction.customerAddress != null &&
          transaction.customerAddress!.isNotEmpty) ...[
        pw.Text(transaction.customerAddress ?? "", style: styleBody),
      ],
      pw.SizedBox(height: 5),
      if (transaction.customerPhone != null &&
          transaction.customerPhone!.isNotEmpty) ...[
        pw.Text(transaction.customerPhone ?? "", style: styleBody),
      ]
    ]),
    pw.SizedBox(height: 30),

    // TABLE: STRICT GRIDS
    pw.Table(
        border: const pw.TableBorder(
          top: pw.BorderSide(color: PdfColors.black, width: 1),
          bottom: pw.BorderSide(color: PdfColors.black, width: 1),
          left: pw.BorderSide(color: PdfColors.black, width: 1),
          right: pw.BorderSide(color: PdfColors.black, width: 1),
          verticalInside: pw.BorderSide(color: PdfColors.black, width: 1),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1.2),
          3: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(
              decoration: const pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black, width: 1))),
              children: [
                _tableHeader('Description',
                    alignment: pw.TextAlign.center, color: PdfColors.black),
                _tableHeader('Qty.',
                    alignment: pw.TextAlign.center, color: PdfColors.black),
                _tableHeader('Unit Price',
                    alignment: pw.TextAlign.center, color: PdfColors.black),
                _tableHeader('Amount',
                    alignment: pw.TextAlign.center, color: PdfColors.black),
              ]),
          ...transaction.items.map((item) {
            return pw.TableRow(children: [
              _tableCell(item.description, alignment: pw.TextAlign.left),
              _tableCell(item.quantity.toString(),
                  alignment: pw.TextAlign.center),
              _tableCell(formatCurrency(item.amount, currencySymbol),
                  alignment: pw.TextAlign.center),
              _tableCell(
                  formatCurrency(item.amount * item.quantity, currencySymbol),
                  alignment: pw.TextAlign.center),
            ]);
          }),
        ]),

    // FOOTER TOTAL BOX
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
      pw.Container(
          width: 200,
          child: pw.Table(
              border: pw.TableBorder(
                left: const pw.BorderSide(color: PdfColors.black, width: 1),
                right: const pw.BorderSide(color: PdfColors.black, width: 1),
                bottom: const pw.BorderSide(color: PdfColors.black, width: 1),
                verticalInside:
                    const pw.BorderSide(color: PdfColors.black, width: 1),
                horizontalInside:
                    const pw.BorderSide(color: PdfColors.black, width: 1),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(children: [
                  _tableHeader('Sub Total',
                      alignment: pw.TextAlign.center, color: PdfColors.black),
                  _tableCell(
                      formatCurrency(
                          transaction.transactionTotal - (transaction.tax ?? 0),
                          currencySymbol),
                      alignment: pw.TextAlign.right),
                ]),
                pw.TableRow(children: [
                  _tableHeader('Tax',
                      alignment: pw.TextAlign.center, color: PdfColors.black),
                  _tableCell(
                      formatCurrency(transaction.tax ?? 0, currencySymbol),
                      alignment: pw.TextAlign.right),
                ]),
                pw.TableRow(children: [
                  _tableHeader('Total Amount',
                      alignment: pw.TextAlign.center, color: PdfColors.black),
                  _tableCell(
                      formatCurrency(
                          transaction.transactionTotal, currencySymbol),
                      alignment: pw.TextAlign.right),
                ]),
              ]))
    ]),
    pw.SizedBox(height: 30),
    pw.Center(
        child: pw.Text("Thank you for shopping with ${businessName ?? "us"}.",
            style: pw.TextStyle(
                font: regularFont,
                fontSize: 10,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700))),
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
