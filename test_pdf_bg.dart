import 'dart:io';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/pdf_service.dart';

void main() async {
  final service = PdfService();
  final profile = BusinessProfile(
    phoneNumber: "123",
    businessName: "Test Org",
    currencyCode: "NGN",
    currencySymbol: "₦",
  );

  final transaction = Transaction(
    customerName: "Jane Doe",
    items: [ReceiptItem(description: "Test Item", amount: 100, quantity: 1)],
    totalAmount: 100,
    date: DateTime.now(),
  );

  final bytes = await service.generateReceipt(profile, transaction,
      themeIndex: 1, layoutIndex: 0);

  await File('test_beige.pdf').writeAsBytes(bytes);
  print('Done writing Beige PDF');
}
