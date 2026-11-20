import 'dart:io';

import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/pdf_service.dart';

/// Writes the receipts shown in the promo video into `samples/promo/`,
/// all from one business so they match:
///
///   dart run bin/promo_receipts.dart
void main() async {
  final pdfService = PdfService();

  final profile = BusinessProfile(
    phoneNumber: '+2348034567890',
    businessName: 'Bisi Provisions',
    businessAddress: 'Shop 12, Wuse Market, Abuja',
    displayPhoneNumber: '0803 456 7890',
    currencyCode: 'NGN',
    currencySymbol: '₦',
    isPremium: true,
  );

  // The bot numbers receipts by day, so every receipt from 20 Nov is
  // R-32800, the number shown in the chat recordings.
  final day = DateTime.utc(2026, 11, 20);

  final indomie = Transaction(
    type: TransactionType.receipt,
    date: day,
    customerName: 'Chidi',
    items: [
      ReceiptItem(description: 'Carton of Indomie', quantity: 5, amount: 9500),
    ],
    totalAmount: 47500,
  );

  final groceries = Transaction(
    type: TransactionType.receipt,
    date: day,
    customerName: 'Mama Ngozi',
    items: [
      ReceiptItem(description: 'Crate of eggs', quantity: 3, amount: 4500),
      ReceiptItem(description: 'Bag of sugar', quantity: 1, amount: 38000),
      ReceiptItem(description: 'Tin of milk', quantity: 2, amount: 1800),
    ],
    totalAmount: 55100,
  );

  final out = Directory('samples/promo')..createSync(recursive: true);
  for (final (name, sale) in [
    ('chidi', indomie),
    ('mama_ngozi', groceries),
  ]) {
    final bytes = await pdfService.generateReceipt(
      profile,
      sale,
      themeIndex: 0,
      layoutIndex: DocumentLayout.studio,
    );
    final file = File('${out.path}/$name.pdf');
    await file.writeAsBytes(bytes);
    stdout.writeln('✓ ${file.path}');
  }
}
