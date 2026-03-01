import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/models/models.dart';

List<pw.Widget> signatureReceipt(
    pw.Context context,
    Transaction transaction,
    pw.MemoryImage? logoImage,
    PdfColor primary,
    PdfColor textColor,
    pw.Font regularFont,
    pw.Font boldFont,
    pw.Font? scriptFont,
    pw.Font? serifFont,
    String? businessName,
    String? businessAddress,
    String? displayPhoneNumber,
    String currencySymbol) {
  final styleLabel =
      pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.grey600);
  final styleBody =
      pw.TextStyle(font: regularFont, fontSize: 10, color: textColor);
  // Removed unused titleStyle

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
                              font: serifFont,
                              fontSize: 24, // Adjusted size for stacked layout
                              color: primary)
                          : pw.TextStyle(
                              font: boldFont, fontSize: 24, color: primary),
                    ),
                    if (businessAddress != null &&
                        businessAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(businessAddress, style: styleBody),
                    ],
                    if (displayPhoneNumber != null &&
                        displayPhoneNumber.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(displayPhoneNumber, style: styleBody),
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 30),

    // BILLED TO Section
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text("BILLED TO:", style: styleLabel),
            pw.SizedBox(height: 5),
            pw.Text(transaction.customerName,
                style: serifFont != null
                    ? pw.TextStyle(font: serifFont)
                    : styleBody.copyWith(
                        fontWeight: pw.FontWeight.bold, fontSize: 10)),
            if (transaction.customerAddress != null &&
                transaction.customerAddress!.isNotEmpty)
              pw.Text(transaction.customerAddress ?? "",
                  style: serifFont != null
                      ? pw.TextStyle(font: serifFont, fontSize: 10)
                      : styleBody.copyWith(color: PdfColors.grey700)),
            if (transaction.customerPhone != null &&
                transaction.customerPhone!.isNotEmpty)
              pw.Text(transaction.customerPhone ?? "",
                  style: serifFont != null
                      ? pw.TextStyle(font: serifFont, fontSize: 10)
                      : styleBody.copyWith(color: PdfColors.grey700)),
          ]),

          // Right: Receipt Meta
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text("RECEIPT NO: ",
                      style: styleLabel.copyWith(color: PdfColors.black)),
                  pw.Text(' R-$uniqueId', style: styleBody),
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
        ]),

    pw.SizedBox(height: 30),

    // TABLE:
    pw.Table(
      border: const pw.TableBorder(
        top: pw.BorderSide.none,
        bottom: pw.BorderSide.none,
        left: pw.BorderSide.none,
        right: pw.BorderSide.none,
        horizontalInside: pw.BorderSide.none,
        verticalInside: pw.BorderSide.none,
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                    color: PdfColors.black,
                    width: 1.5,
                    style: pw.BorderStyle.solid),
                bottom: pw.BorderSide(
                    color: PdfColors.black,
                    width: 1.5,
                    style: pw.BorderStyle.solid),
              ),
            ),
            children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: _tableHeader('DESCRIPTION',
                      alignment: pw.TextAlign.left, color: PdfColors.black)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: _tableHeader('PRICE',
                      alignment: pw.TextAlign.center, color: PdfColors.black)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: _tableHeader('QTY',
                      alignment: pw.TextAlign.center, color: PdfColors.black)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: _tableHeader('TOTAL',
                      alignment: pw.TextAlign.right, color: PdfColors.black)),
            ]),
        ...transaction.items.map((item) {
          return pw.TableRow(
            children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: pw.Text(item.description, style: styleBody)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: pw.Text(formatCurrency(item.amount, currencySymbol),
                      style: styleBody, textAlign: pw.TextAlign.center)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: pw.Text(item.quantity.toString(),
                      style: styleBody, textAlign: pw.TextAlign.center)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: pw.Text(
                      formatCurrency(
                          item.amount * item.quantity, currencySymbol),
                      style: styleBody,
                      textAlign: pw.TextAlign.right)),
            ],
          );
        }),
      ],
    ),

    pw.SizedBox(height: 5),

    pw.Container(
        decoration: const pw.BoxDecoration(
            border: pw.Border(
          top: pw.BorderSide(
              color: PdfColors.black, width: 1.5, style: pw.BorderStyle.solid),
          bottom: pw.BorderSide(
              color: PdfColors.black, width: 1.5, style: pw.BorderStyle.solid),
        )),
        padding: const pw.EdgeInsets.symmetric(vertical: 10),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8),
                  child: pw.Text("SUBTOTAL",
                      style: styleLabel.copyWith(color: PdfColors.black))),
              pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 8),
                  child: pw.Text(
                      formatCurrency(
                          transaction.transactionTotal - (transaction.tax ?? 0),
                          currencySymbol),
                      style: styleBody.copyWith(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black))),
            ])),
    pw.SizedBox(height: 15),

    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Container()),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text("Tax", style: styleLabel),
              pw.SizedBox(width: 30),
              pw.Text(formatCurrency(transaction.tax ?? 0, currencySymbol),
                  style: styleBody),
            ]),
            pw.SizedBox(height: 5),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text("TOTAL",
                  style: styleLabel.copyWith(
                      color: PdfColors.black, fontSize: 14)),
              pw.SizedBox(width: 30),
              pw.Text(
                  formatCurrency(transaction.transactionTotal, currencySymbol),
                  style: styleBody.copyWith(
                      fontWeight: pw.FontWeight.bold, fontSize: 14)),
            ]),
          ])
        ]),
    pw.SizedBox(height: 40),
    if (scriptFont != null)
      pw.Center(
        child: pw.Text("thank you for shopping $businessName",
            style:
                pw.TextStyle(font: scriptFont, fontSize: 10, color: primary)),
      )
  ];
}

List<pw.Widget> signatureInvoice(
    pw.Context context,
    Transaction transaction,
    pw.MemoryImage? logoImage,
    PdfColor primary,
    PdfColor textColor,
    pw.Font regularFont,
    pw.Font boldFont,
    pw.Font? scriptFont,
    pw.Font? serifFont,
    String? businessName,
    String? businessAddress,
    String? displayPhoneNumber,
    String? bankName,
    String? accountNumber,
    String? accountName,
    String currencySymbol) {
  final styleLabel =
      pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.grey600);
  final styleBody =
      pw.TextStyle(font: regularFont, fontSize: 10, color: textColor);
  final titleStyle = scriptFont != null
      ? pw.TextStyle(font: scriptFont, fontSize: 26, color: primary)
      : pw.TextStyle(font: boldFont, fontSize: 26, color: primary);

  final uniqueId =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString()
          .padLeft(5, '1')
          .substring(0, 5);

  return [
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
            pw.Text("INVOICE",
                style: titleStyle.copyWith(color: PdfColors.black)),
            pw.SizedBox(height: 20),
            pw.Text("BILL TO:", style: styleLabel),
            pw.SizedBox(height: 5),
            pw.Text(transaction.customerName,
                style: styleBody.copyWith(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                    font: serifFont)),
            if (transaction.customerAddress != null &&
                transaction.customerAddress!.isNotEmpty)
              pw.Text(transaction.customerAddress ?? "",
                  style: styleBody.copyWith(
                      color: PdfColors.grey700, fontSize: 10, font: serifFont)),
            if (transaction.customerPhone != null &&
                transaction.customerPhone!.isNotEmpty)
              pw.Text(transaction.customerPhone ?? "",
                  style: styleBody.copyWith(
                      color: PdfColors.grey700, fontSize: 10, font: serifFont)),
            pw.SizedBox(height: 15),
            pw.Container(
                width: 200,
                child: pw.Divider(
                    color: PdfColor.fromHex('#D2BAA3'), thickness: 1)),
            pw.SizedBox(height: 15),
            pw.Text("FROM:", style: styleLabel),
            pw.SizedBox(height: 5),
            pw.Text(businessName ?? "BUSINESS NAME",
                style: serifFont != null
                    ? pw.TextStyle(
                        font: serifFont,
                        fontSize: 14,
                        color: textColor,
                        fontWeight: pw.FontWeight.bold)
                    : styleBody.copyWith(
                        fontWeight: pw.FontWeight.bold, fontSize: 12)),
            if (businessAddress != null && businessAddress.isNotEmpty)
              pw.Text(businessAddress,
                  style: serifFont != null
                      ? pw.TextStyle(
                          font: serifFont,
                          fontSize: 10,
                          color: PdfColors.grey700)
                      : styleBody.copyWith(color: PdfColors.grey700)),
            if (displayPhoneNumber != null && displayPhoneNumber.isNotEmpty)
              pw.Text(displayPhoneNumber,
                  style: serifFont != null
                      ? pw.TextStyle(
                          font: serifFont,
                          fontSize: 10,
                          color: PdfColors.grey700)
                      : styleBody.copyWith(color: PdfColors.grey700)),
          ])),
      pw.SizedBox(width: 40),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Text("INVOICE NO: ", style: styleLabel.copyWith(color: primary)),
          pw.Text('INV-$uniqueId', style: styleBody),
        ]),
        pw.SizedBox(height: 5),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Text("date: ", style: styleLabel.copyWith(color: primary)),
          pw.Text(DateFormat('MM.dd.yyyy').format(transaction.date),
              style: styleBody),
        ]),
        if (transaction.dueDate != null) ...[
          pw.SizedBox(height: 5),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text("due date: ", style: styleLabel.copyWith(color: primary)),
            pw.Text(DateFormat('MM.dd.yyyy').format(transaction.dueDate!),
                style: styleBody),
          ]),
        ],
        if (logoImage != null) ...[
          pw.SizedBox(height: 20),
          pw.ClipOval(
            child: pw.Container(
              height: 100,
              width: 100,
              child: pw.Image(logoImage, fit: pw.BoxFit.cover),
            ),
          ),
        ],
      ])
    ]),
    pw.SizedBox(height: 40),
    pw.Table(
        border: const pw.TableBorder(
          top: pw.BorderSide.none,
          bottom: pw.BorderSide.none,
          left: pw.BorderSide.none,
          right: pw.BorderSide.none,
          horizontalInside: pw.BorderSide.none,
          verticalInside: pw.BorderSide.none,
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(
                      color: PdfColors.black,
                      width: 1.5,
                      style: pw.BorderStyle.solid),
                  bottom: pw.BorderSide(
                      color: PdfColors.black,
                      width: 1.5,
                      style: pw.BorderStyle.solid),
                ),
              ),
              children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: _tableHeader('DESCRIPTION',
                        alignment: pw.TextAlign.left, color: PdfColors.black)),
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: _tableHeader('PRICE',
                        alignment: pw.TextAlign.center,
                        color: PdfColors.black)),
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: _tableHeader('QTY',
                        alignment: pw.TextAlign.center,
                        color: PdfColors.black)),
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: _tableHeader('TOTAL',
                        alignment: pw.TextAlign.right, color: PdfColors.black)),
              ]),
          ...transaction.items.map((item) {
            return pw.TableRow(children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: pw.Text(item.description, style: styleBody)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: pw.Text(formatCurrency(item.amount, currencySymbol),
                      style: styleBody, textAlign: pw.TextAlign.center)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: pw.Text(item.quantity.toString(),
                      style: styleBody, textAlign: pw.TextAlign.center)),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: pw.Text(
                      formatCurrency(
                          item.amount * item.quantity, currencySymbol),
                      style: styleBody,
                      textAlign: pw.TextAlign.right)),
            ]);
          }),
        ]),
    pw.SizedBox(height: 5),
    pw.Container(
        decoration: const pw.BoxDecoration(
            border: pw.Border(
          top: pw.BorderSide(
              color: PdfColors.black, width: 1.5, style: pw.BorderStyle.solid),
          bottom: pw.BorderSide(
              color: PdfColors.black, width: 1.5, style: pw.BorderStyle.solid),
        )),
        padding: const pw.EdgeInsets.symmetric(vertical: 10),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8),
                  child: pw.Text("SUBTOTAL",
                      style: styleLabel.copyWith(color: PdfColors.black))),
              pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 8),
                  child: pw.Text(
                      formatCurrency(
                          transaction.transactionTotal - (transaction.tax ?? 0),
                          currencySymbol),
                      style: styleBody.copyWith(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black))),
            ])),
    pw.SizedBox(height: 15),
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.SizedBox(height: 30),
                if (bankName != null || transaction.bankName != null) ...[
                  pw.Text("PAYMENT OPTIONS:",
                      style: styleLabel.copyWith(
                          color: PdfColors.black,
                          fontSize: 12,
                          fontStyle: pw.FontStyle.italic)),
                  pw.SizedBox(height: 10),
                  pw.Text(
                      'Bank Name: ${bankName ?? transaction.bankName ?? ""}',
                      style: styleBody),
                  pw.SizedBox(height: 3),
                  pw.Text(
                      'Account Name: ${accountName ?? transaction.accountName ?? ""}',
                      style: styleBody),
                  pw.SizedBox(height: 3),
                  pw.Text(
                      "Account No: ${accountNumber ?? transaction.accountNumber}",
                      style: styleBody),
                ]
              ])),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text("Tax", style: styleLabel),
              pw.SizedBox(width: 30),
              pw.Text(formatCurrency(transaction.tax ?? 0, currencySymbol),
                  style: styleBody),
            ]),
            pw.SizedBox(height: 5),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text("TOTAL",
                  style: styleLabel.copyWith(
                      color: PdfColors.black, fontSize: 12)),
              pw.SizedBox(width: 30),
              pw.Text(
                  formatCurrency(transaction.transactionTotal, currencySymbol),
                  style: styleBody.copyWith(
                      fontWeight: pw.FontWeight.bold, fontSize: 12)),
            ]),
          ])
        ]),
    if (scriptFont != null) ...[
      pw.SizedBox(height: 40),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text("thank you!",
              style:
                  pw.TextStyle(font: scriptFont, fontSize: 14, color: primary)),
        ],
      )
    ]
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
