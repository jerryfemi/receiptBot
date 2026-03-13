import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/models/models.dart';

List<pw.Widget> corporateInvoice(
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

  final headerBgColor = PdfColor.fromHex(
      '#F4F1E9'); // Light beige fill color closely matching Image 1

  final uniqueIdString =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString();
  final uniqueId = uniqueIdString.length >= 5
      ? uniqueIdString.substring(uniqueIdString.length - 5)
      : uniqueIdString.padLeft(5, '0');

  return [
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text((businessName ?? "YOUR COMPANY NAME").toUpperCase(),
                    style: serifFont != null
                        ? pw.TextStyle(
                            font: serifFont,
                            fontSize: 24,
                            color: PdfColors.black)
                        : styleTitle.copyWith(fontSize: 24)),
                pw.SizedBox(height: 5),
                pw.Text(businessAddress ?? "YOUR BUSINESS ADDRESS",
                    style: serifFont != null
                        ? pw.TextStyle(
                            font: serifFont, fontSize: 12, color: textColor)
                        : styleBody.copyWith(fontSize: 12)),
              ])),
          if (logoImage != null)
            pw.ClipOval(
              child: pw.Container(
                height: 80,
                width: 80,
                child: pw.Image(logoImage, fit: pw.BoxFit.cover),
              ),
            )
        ]),
    pw.SizedBox(height: 30),
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text("BILL TO:",
                style: serifFont != null
                    ? pw.TextStyle(font: serifFont)
                    : styleLabel.copyWith(
                        fontSize: 12,
                      )),
            pw.SizedBox(height: 4),
            pw.Text(transaction.customerName,
                style: serifFont != null
                    ? pw.TextStyle(font: serifFont, fontSize: 10)
                    : styleBody.copyWith(fontSize: 10)),
            if (transaction.customerAddress != null &&
                transaction.customerAddress!.isNotEmpty)
              pw.Text(transaction.customerAddress!,
                  style: serifFont != null
                      ? pw.TextStyle(font: serifFont, fontSize: 10)
                      : styleBody),
            if (transaction.customerPhone != null &&
                transaction.customerPhone!.isNotEmpty)
              pw.Text(transaction.customerPhone!,
                  style: serifFont != null
                      ? pw.TextStyle(font: serifFont, fontSize: 10)
                      : styleBody),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text("INVOICE NO: ", style: styleLabel.copyWith(fontSize: 12)),
              pw.Text("INV-$uniqueId",
                  style: styleBody.copyWith(
                      fontSize: 10, color: PdfColors.grey700)),
            ]),
            pw.SizedBox(height: 4),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text("DATE: ", style: styleLabel.copyWith(fontSize: 12)),
              pw.Text(DateFormat('MM.dd.yyyy').format(transaction.date),
                  style: styleBody
                      .copyWith(fontSize: 10)
                      .copyWith(color: PdfColors.grey700)),
            ]),
            if (transaction.dueDate != null) ...[
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                pw.Text("DUE-DATE: ", style: styleLabel.copyWith(fontSize: 12)),
                pw.Text(DateFormat('MM.dd.yyyy').format(transaction.dueDate!),
                    style: styleBody
                        .copyWith(fontSize: 10)
                        .copyWith(color: PdfColors.grey700)),
              ]),
            ]
          ])
        ]),
    pw.SizedBox(height: 30),
    pw.Center(
      child: pw.Text("INVOICE",
          style: styleTitle.copyWith(fontSize: 10, color: PdfColors.grey600)),
    ),
    pw.SizedBox(height: 10),
    pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(
              decoration: pw.BoxDecoration(color: headerBgColor),
              children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("ITEM DESCRIPTION",
                        style: styleLabel, textAlign: pw.TextAlign.center)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("PRICE",
                        style: styleLabel, textAlign: pw.TextAlign.center)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("QTY",
                        style: styleLabel, textAlign: pw.TextAlign.center)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("TOTAL",
                        style: styleLabel, textAlign: pw.TextAlign.center)),
              ]),
          ...transaction.items.map((item) {
            return pw.TableRow(children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(item.description,
                      style: styleBody, textAlign: pw.TextAlign.left)),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(formatCurrency(item.amount, currencySymbol),
                      style: styleBody, textAlign: pw.TextAlign.center)),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(item.quantity.toString(),
                      style: styleBody, textAlign: pw.TextAlign.center)),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                      formatCurrency(
                          item.amount * item.quantity, currencySymbol),
                      style: styleBody,
                      textAlign: pw.TextAlign.center)),
            ]);
          }),
        ]),
    pw.SizedBox(height: 20),
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
      pw.Container(
          width: 200,
          child: pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                    decoration: pw.BoxDecoration(color: headerBgColor),
                    children: [
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text("SUBTOTAL :", style: styleLabel)),
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                              formatCurrency(
                                  transaction.transactionTotal -
                                      (transaction.tax ?? 0),
                                  currencySymbol),
                              style: styleBody,
                              textAlign: pw.TextAlign.right)),
                    ]),
                if (transaction.tax != null && transaction.tax! > 0)
                  pw.TableRow(
                      decoration: pw.BoxDecoration(color: headerBgColor),
                      children: [
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text("TAX :", style: styleLabel)),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                                formatCurrency(
                                    transaction.tax!, currencySymbol),
                                style: styleBody,
                                textAlign: pw.TextAlign.right)),
                      ]),
                pw.TableRow(
                    decoration: pw.BoxDecoration(color: headerBgColor),
                    children: [
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text("TOTAL :", style: styleLabel)),
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                              formatCurrency(
                                transaction.transactionTotal,
                                currencySymbol,
                              ),
                              style: styleBody,
                              textAlign: pw.TextAlign.right)),
                    ]),
              ]))
    ]),
    pw.SizedBox(height: 30),
    if (bankName != null || transaction.bankName != null) ...[
      pw.Text("PAYMENT METHOD:", style: styleLabel),
      pw.SizedBox(height: 5),
      pw.Text("Bank Name: ${bankName ?? transaction.bankName ?? ''}",
          style: serifFont != null ? pw.TextStyle(font: serifFont) : styleBody),
      pw.SizedBox(height: 2),
      pw.Text(
          "Account Number: ${accountNumber ?? transaction.accountNumber ?? ''}",
          style: serifFont != null ? pw.TextStyle(font: serifFont) : styleBody),
      pw.SizedBox(height: 2),
      pw.Text("Account Name: ${accountName ?? transaction.accountName ?? ''}",
          style: serifFont != null ? pw.TextStyle(font: serifFont) : styleBody),
      pw.SizedBox(height: 20),
    ] else ...[
      // Default Payment options if missing
      pw.Text("PAYMENT METHOD:",
          style:
              serifFont != null ? pw.TextStyle(font: serifFont) : styleLabel),
      pw.SizedBox(height: 5),
      pw.Text("Cash / Card / Other applicable method",
          style: serifFont != null ? pw.TextStyle(font: serifFont) : styleBody),
      pw.SizedBox(height: 20),
    ],
  ];
}

List<pw.Widget> corporateReceipt(
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

  final headerBgColor = PdfColor.fromHex(
      '#F4F1E9'); // Light beige fill color closely matching Image 1

  final uniqueIdString =
      (transaction.hashCode ^ transaction.date.millisecondsSinceEpoch)
          .abs()
          .toString();
  final uniqueId = uniqueIdString.length >= 5
      ? uniqueIdString.substring(uniqueIdString.length - 5)
      : uniqueIdString.padLeft(5, '0');

  return [
    // GLOBAL RECEIPT HEADER
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
                              font: serifFont, fontSize: 24, color: primary)
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
            pw.Text("BILLED TO:", style: styleLabel.copyWith(fontSize: 12)),
            pw.SizedBox(height: 4),
            pw.Text(transaction.customerName,
                style: serifFont != null
                    ? pw.TextStyle(font: serifFont, fontSize: 10)
                    : styleBody.copyWith(fontSize: 10)),
            if (transaction.customerAddress != null &&
                transaction.customerAddress!.isNotEmpty)
              pw.Text(transaction.customerAddress ?? "",
                  style: serifFont != null
                      ? pw.TextStyle(font: serifFont, fontSize: 10)
                      : styleBody),
            if (transaction.customerPhone != null &&
                transaction.customerPhone!.isNotEmpty)
              pw.Text(transaction.customerPhone ?? "",
                  style: serifFont != null
                      ? pw.TextStyle(font: serifFont, fontSize: 10)
                      : styleBody),
          ]),

          // receipt number
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
        ]),
    pw.SizedBox(height: 30),
    pw.Center(
      child: pw.Text("RECEIPT",
          style: styleTitle.copyWith(fontSize: 10, color: PdfColors.grey600)),
    ),
    pw.SizedBox(height: 10),
    pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(
              decoration: pw.BoxDecoration(color: headerBgColor),
              children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("ITEM DESCRIPTION",
                        style: styleLabel, textAlign: pw.TextAlign.center)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("PRICE",
                        style: styleLabel, textAlign: pw.TextAlign.center)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("QTY",
                        style: styleLabel, textAlign: pw.TextAlign.center)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("TOTAL",
                        style: styleLabel, textAlign: pw.TextAlign.center)),
              ]),
          ...transaction.items.map((item) {
            return pw.TableRow(children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(item.description,
                      style: styleBody, textAlign: pw.TextAlign.left)),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(formatCurrency(item.amount, currencySymbol),
                      style: styleBody, textAlign: pw.TextAlign.center)),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(item.quantity.toString(),
                      style: styleBody, textAlign: pw.TextAlign.center)),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                      formatCurrency(
                          item.amount * item.quantity, currencySymbol),
                      style: styleBody,
                      textAlign: pw.TextAlign.center)),
            ]);
          }),
        ]),
    pw.SizedBox(height: 20),
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
      pw.Container(
          width: 200,
          child: pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                    decoration: pw.BoxDecoration(color: headerBgColor),
                    children: [
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text("SUBTOTAL :", style: styleLabel)),
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                              formatCurrency(
                                  transaction.transactionTotal -
                                      (transaction.tax ?? 0),
                                  currencySymbol),
                              style: styleBody,
                              textAlign: pw.TextAlign.right)),
                    ]),
                if (transaction.tax != null && transaction.tax! > 0)
                  pw.TableRow(
                      decoration: pw.BoxDecoration(color: headerBgColor),
                      children: [
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text("TAX :", style: styleLabel)),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                                formatCurrency(
                                    transaction.tax!, currencySymbol),
                                style: styleBody,
                                textAlign: pw.TextAlign.right)),
                      ]),
                pw.TableRow(
                    decoration: pw.BoxDecoration(color: headerBgColor),
                    children: [
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text("TOTAL :", style: styleLabel)),
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                              formatCurrency(
                                  transaction.transactionTotal, currencySymbol),
                              style: styleBody,
                              textAlign: pw.TextAlign.right)),
                    ]),
              ]))
    ]),

    pw.SizedBox(height: 20),
    pw.Center(
        child: pw.Text("Thank you for shopping with ${businessName ?? "us"}.",
            style: pw.TextStyle(
                font: regularFont,
                fontSize: 10,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700))),
  ];
}
