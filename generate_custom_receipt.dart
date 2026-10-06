import 'dart:io';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/pdf_service.dart';

void main() async {
  print('Generating Black Rock Receipts & Invoices...');

  final pdfService = PdfService();

  // We set isPremium: true here so the layouts are actually applied.
  // Otherwise, the PdfService forces everything to the Corporate layout!
  final BusinessProfile profile = BusinessProfile(
    phoneNumber: '1234567890',
    currencyCode: 'NGN', 
    currencySymbol: '₦',
    isPremium: true, 
  );

  final List<ReceiptItem> items = [
    ReceiptItem(description: 'Cameras', quantity: 2, amount: 40000),
    ReceiptItem(description: 'Lenses', quantity: 2, amount: 15000),
    ReceiptItem(description: 'Gimbal', quantity: 1, amount: 3000),
    ReceiptItem(description: 'Tripod', quantity: 1, amount: 10000),
    ReceiptItem(description: 'Light', quantity: 1, amount: 20000),
    ReceiptItem(description: 'Logistics', quantity: 1, amount: 50000),
    ReceiptItem(description: 'Services', quantity: 1, amount: 300000),
  ];

  double totalAmount = 0;
  for (final item in items) {
    totalAmount += item.quantity * item.amount;
  }

  // Create Invoice transaction
  final Transaction invoice = Transaction(
    customerName: 'Valued Customer',
    type: TransactionType.invoice,
    items: items,
    totalAmount: totalAmount,
    date: DateTime.now(),
  );

  // Create Receipt transaction
  final layouts = ['Default', 'Signature', 'Simple', 'Corporate'];

  for (int i = 0; i < layouts.length; i++) {
    final Organization org = Organization(
      id: 'org_black_rock',
      inviteCode: 'BLACKROCK1',
      businessName: 'Black Rock',
      businessAddress: '',
      displayPhoneNumber: '',
      layoutIndex: i, 
    );
    
    // Generate Invoice
    final invoiceBytes = await pdfService.generateReceipt(
        profile, invoice, themeIndex: 0, layoutIndex: i, org: org);
    final invoiceFilename = 'invoice_${layouts[i].toLowerCase()}.pdf';
    await File(invoiceFilename).writeAsBytes(invoiceBytes);
    print('✅ Generated: $invoiceFilename');

  }
}
