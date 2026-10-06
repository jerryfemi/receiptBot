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

  final transaction = Transaction(
    type: TransactionType.invoice,
    date: DateTime.now(),
    dueDate: DateTime.now().add(const Duration(days: 14)),
    customerName: 'Eleanor Vance',
    customerAddress: '456 Elite Way, Los Angeles, CA 90001',
    items: [
      ReceiptItem(description: 'Premium Consultation', quantity: 1, amount: 250.0),
      ReceiptItem(description: 'Signature Facial Treatment', quantity: 2, amount: 150.0),
      ReceiptItem(description: 'Luxury Skincare Set', quantity: 1, amount: 450.0),
    ],
    tax: 50.0,
    discount: 50.0,
    totalAmount: 1000.0,
    notes: 'Thank you for visiting Luxe Aesthetics. We look forward to seeing you again.',
    terms: 'Payment is due within 14 days. Late payments may incur a 5% fee. No refunds on services rendered.',
  );

  final themes = [
    'Ocean_Blue',
    'Sand_Beige',
    'Midnight_Navy',
    'Sage_Green',
    'Charcoal_Onyx',
    'Deep_Burgundy',
  ];

  for (int i = 0; i < themes.length; i++) {
    try {
      print('Generating Signature Invoice for ${themes[i]}...');
      final bytes = await pdfService.generateReceipt(
        profile,
        transaction,
        themeIndex: i,
        layoutIndex: 1, // Signature layout
      );
      final file = File('signature_invoice_${themes[i]}.pdf');
      await file.writeAsBytes(bytes);
      print('Saved ${file.path}');
    } catch (e) {
      print('Error generating ${themes[i]}: $e');
    }
  }
}
