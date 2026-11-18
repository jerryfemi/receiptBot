import 'dart:io';
import 'package:receipt_bot/services/pdf_service.dart';
import 'package:receipt_bot/models/models.dart';

void main() async {
  final pdfService = PdfService();

  final profile = BusinessProfile(
    phoneNumber: '+1234567890',
    businessName: 'Luxe Aesthetics',
    businessAddress: '123 Premium Blvd, Beverly Hills, CA 90210',
    displayPhoneNumber: '+1 (555) 123-4567',
    currencyCode: 'USD',
    currencySymbol: '\$',
    bankName: 'Chase Bank',
    accountNumber: '123456789',
    accountName: 'Luxe Aesthetics LLC',
    isPremium: true,
  );

  final items = [
    ReceiptItem(description: 'Premium Consultation', quantity: 1, amount: 250.0),
    ReceiptItem(description: 'Signature Facial Treatment', quantity: 2, amount: 150.0),
    ReceiptItem(description: 'Luxury Skincare Set', quantity: 1, amount: 450.0),
  ];

  final invoice = Transaction(
    type: TransactionType.invoice,
    date: DateTime.now(),
    dueDate: DateTime.now().add(const Duration(days: 14)),
    customerName: 'Eleanor Vance',
    customerAddress: '456 Elite Way, Los Angeles, CA 90001',
    items: items,
    tax: 50.0,
    discount: 50.0,
    totalAmount: 1000.0,
    notes: 'Thank you for visiting Luxe Aesthetics. We look forward to seeing you again.',
    terms: 'Payment is due within 14 days. Late payments may incur a 5% fee. No refunds on services rendered.',
  );

  final receipt = Transaction(
    type: TransactionType.receipt,
    date: DateTime.now(),
    customerName: 'Eleanor Vance',
    customerAddress: '456 Elite Way, Los Angeles, CA 90001',
    items: items,
    tax: 50.0,
    discount: 50.0,
    totalAmount: 1000.0,
    notes: 'Thank you for visiting Luxe Aesthetics. We look forward to seeing you again.',
    terms: 'Payment is due within 14 days. Late payments may incur a 5% fee. No refunds on services rendered.',
  );

  final layouts = ['default', 'signature', 'simple', 'corporate']; // Index matches pdf_service.dart
  final themeIndex = 2; // Midnight Navy

  for (int i = 0; i < layouts.length; i++) {
    try {
      print('Generating ${layouts[i]} Invoice...');
      final invBytes = await pdfService.generateReceipt(
        profile,
        invoice,
        themeIndex: themeIndex,
        layoutIndex: i,
      );
      await File('${layouts[i]}_invoice.pdf').writeAsBytes(invBytes);
      
      print('Generating ${layouts[i]} Receipt...');
      final recBytes = await pdfService.generateReceipt(
        profile,
        receipt,
        themeIndex: themeIndex,
        layoutIndex: i,
      );
      await File('${layouts[i]}_receipt.pdf').writeAsBytes(recBytes);
    } catch (e) {
      print('Error generating ${layouts[i]}: $e');
    }
  }
}
