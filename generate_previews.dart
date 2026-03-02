import 'dart:io';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/pdf_service.dart';

void main() async {
  print('Generating dummy PDFs...');

  // Initialize the PDF service
  final pdfService = PdfService();

  // Create a dummy organization profile
  final BusinessProfile profile = BusinessProfile(
    phoneNumber: '1234567890',
    currencyCode: 'USD',
    currencySymbol: '\$',
  );

  // We will recreate this object in the loop to pass the layoutIndex
  Organization createDummyOrg(int index) {
    return Organization(
      id: 'dummy_org',
      inviteCode: 'DUMMY1',
      businessName: 'Acme Corp',
      businessAddress: '123 Business Rd, Suite 100\nMetropolis, NY 10001',
      displayPhoneNumber: '+1-555-0199',
      logoUrl:
          'public/logos/ms-office-logo-on-transparent-background-free-vector.jpg',
      layoutIndex: index,
    );
  }

  // Create dummy items
  final List<ReceiptItem> items = [
    ReceiptItem(
        description: 'Premium Widget Model X', quantity: 2, amount: 499.99),
    ReceiptItem(
        description: 'Installation Service (Hourly)',
        quantity: 4,
        amount: 75.00),
    ReceiptItem(
        description: 'Extended Warranty - 1 Year', quantity: 1, amount: 99.50),
    ReceiptItem(description: 'Shipping & Handling', quantity: 1, amount: 15.00),
  ];

  // Calculate total
  double subTotal = 0;
  for (var i in items) {
    subTotal += i.quantity * i.amount;
  }
  double tax = subTotal * 0.08; // 8% tax
  double total = subTotal + tax;

  // Create dummy Receipt
  final Transaction receipt = Transaction(
    customerName: 'John Doe',
    customerAddress: '456 Client Avenue\nCustomer City, ST 12345',
    customerPhone: '+1-555-0288',
    type: TransactionType.receipt,
    items: items,
    tax: tax,
    totalAmount: total,
    date: DateTime.now(),
  );

  // Create dummy Invoice
  final Transaction invoice = Transaction(
    customerName: 'Jane Smith',
    customerAddress: '789 Client Avenue\nCustomer City, ST 12345',
    customerPhone: '+1-555-0299',
    type: TransactionType.invoice,
    items: items,
    tax: tax,
    totalAmount: total,
    date: DateTime.now(),
    dueDate: DateTime.now().add(Duration(days: 30)),
    bankName: 'First National Bank',
    accountName: 'Acme Corp',
    accountNumber: '000123456789',
  );

  final layouts = ['Default', 'Signature', 'Simple', 'Corporate'];
  final outputDir = Directory('preview_pdfs');
  if (!await outputDir.exists()) {
    await outputDir.create();
  }

  for (int i = 0; i < layouts.length; i++) {
    print('Generating ${layouts[i]} Receipt...');
    final currentOrg = createDummyOrg(i);
    final receiptBytes = await pdfService.generateReceipt(profile, receipt,
        themeIndex: 0, layoutIndex: i, org: currentOrg);
    await File('preview_pdfs/${layouts[i].toLowerCase()}_receipt.pdf')
        .writeAsBytes(receiptBytes);

    print('Generating ${layouts[i]} Invoice...');
    final invoiceBytes = await pdfService.generateReceipt(profile, invoice,
        themeIndex: 0, layoutIndex: i, org: currentOrg);
    await File('preview_pdfs/${layouts[i].toLowerCase()}_invoice.pdf')
        .writeAsBytes(invoiceBytes);
  }

  print('\n✅ All 8 PDFs generated successfully in the "preview_pdfs" folder!');
}
