import 'dart:io';
import 'package:receipt_bot/services/pdf_service.dart';
import 'package:receipt_bot/models/models.dart';

void main() async {
  final pdfService = PdfService();

  final profile = BusinessProfile(
    phoneNumber: '',
    businessName: 'BLACK ROCK',
    businessAddress: '',
    displayPhoneNumber: '',
    currencyCode: 'NGN',
    currencySymbol: '₦',
    isPremium: true,
  );

  final items = [
    ReceiptItem(
      description: 'Gear (2 Cameras & Accessories)',
      quantity: 1,
      amount: 415000.0,
    ),
    ReceiptItem(
      description: 'Production: Videographers',
      quantity: 2,
      amount: 450000.0,
    ),
    ReceiptItem(
      description: 'Post-Production',
      quantity: 1,
      amount: 800000.0,
    ),
  ];

  final invoice = Transaction(
    type: TransactionType.invoice,
    date: DateTime.now(),
    customerName: 'Valued Customer',
    items: items,
    totalAmount: 2115000.0,
    amountInWords: 'Two Million One Hundred and Fifteen Thousand Naira Only',
    notes: 'Deliverables: One cinematic recap',
  );

  final layoutIndex = 3; // Corporate layout
  final themeIndex = 5; // Deep Burgundy
  
  try {
    print('Generating Corporate Invoice for theme: Deep Burgundy...');
    
    final invBytes = await pdfService.generateReceipt(
      profile,
      invoice,
      themeIndex: themeIndex,
      layoutIndex: layoutIndex,
    );
    await File('black_rock_invoice.pdf').writeAsBytes(invBytes);
    await File('black_rock_invoice_Deep_Burgundy.pdf').writeAsBytes(invBytes);
    print('Done!');
  } catch (e) {
    print('Error generating: $e');
  }
}
