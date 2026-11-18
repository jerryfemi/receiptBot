import 'dart:io';

import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/pdf_service.dart';

/// Writes a sample receipt and invoice for every layout into `samples/`,
/// so a design change can be checked without sending a WhatsApp message.
///
///   dart run bin/generate_all_layouts.dart
void main() async {
  final pdfService = PdfService();

  final profile = BusinessProfile(
    phoneNumber: '+2348034567890',
    businessName: 'Adé Electronics',
    businessAddress: '14 Allen Avenue, Ikeja, Lagos',
    displayPhoneNumber: '0803 456 7890',
    currencyCode: 'NGN',
    currencySymbol: '₦',
    bankName: 'GTBank',
    accountNumber: '0123456789',
    accountName: 'Adé Electronics Ltd',
    isPremium: true,
  );

  final items = [
    ReceiptItem(description: 'Canon EOS R6 camera', quantity: 3, amount: 500000),
    ReceiptItem(description: 'Manfrotto tripod', quantity: 1, amount: 350000),
  ];

  final now = DateTime.now();
  final receipt = Transaction(
    type: TransactionType.receipt,
    date: now,
    customerName: 'John Okafor',
    items: items,
    discount: 50000,
    totalAmount: 1800000,
  );
  final invoice = Transaction(
    type: TransactionType.invoice,
    date: now,
    dueDate: now.add(const Duration(days: 14)),
    customerName: 'John Okafor',
    items: items,
    discount: 50000,
    totalAmount: 1800000,
    notes: 'Thank you for your business.',
    terms: 'Payment is due within 14 days.',
  );

  const layouts = {
    DocumentLayout.studio: 'studio',
    DocumentLayout.signature: 'signature',
    DocumentLayout.market: 'market',
    DocumentLayout.till: 'till',
  };
  const themeIndex = 5; // Deep Burgundy, used by Signature

  final out = Directory('samples')..createSync();
  for (final MapEntry(key: index, value: name) in layouts.entries) {
    for (final (kind, sale) in [('receipt', receipt), ('invoice', invoice)]) {
      try {
        final bytes = await pdfService.generateReceipt(
          profile,
          sale,
          themeIndex: themeIndex,
          layoutIndex: index,
        );
        final file = File('${out.path}/${name}_$kind.pdf');
        await file.writeAsBytes(bytes);
        stdout.writeln('✓ ${file.path}');
      } catch (e, stack) {
        stderr.writeln('✗ $name $kind: $e\n$stack');
      }
    }
  }
}
