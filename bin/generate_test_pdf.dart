// import 'dart:io';
// import 'package:receipt_bot/pdf_service.dart';
// import 'package:receipt_bot/models.dart';
// import 'package:pdf/widgets.dart'
//     as pw; // For fonts if needed, but not directly used here

// void main() async {
//   final pdfService = PdfService();

//   // Dummy Business Profile
//   final profile = BusinessProfile(
//     businessName: 'Test Business',
//     businessAddress: '123 Test St, Test City',
//     phoneNumber: '+1234567890',
//     currencySymbol: '₦',
//     logoUrl: null, // Test null logo safety
//   );

//   // Dummy Transaction (Invoice)
//   final invoice = Transaction(
//     type: TransactionType.invoice,
//     date: DateTime.now(),
//     customerName: 'John Doe',
//     items: List.generate(
//         20,
//         (index) => Item(
//               // Generate many items to test pagination
//               description: 'Item $index',
//               quantity: 1,
//               amount: 250.0,
//             )), totalAmount: null,
//   );

//   // Dummy Transaction (Receipt)
//   final receipt = Transaction(
//     type: TransactionType.receipt,
//     amount: 1500.0,
//     date: DateTime.now(),
//     customerName: 'Jane Smith',
//     items: [
//       Item(description: 'Service A', quantity: 2, amount: 500.0),
//       Item(description: 'Product B', quantity: 1, amount: 500.0),
//     ],
//   );

//   try {
//     print('Generating Invoice PDF...');
//     final invoiceBytes = await pdfService.generateReceipt(profile, invoice,
//         themeIndex: 1); // Beige
//     File('test_invoice.pdf').writeAsBytesSync(invoiceBytes);
//     print('Invoice generated: test_invoice.pdf');

//     print('Generating Receipt PDF...');
//     final receiptBytes = await pdfService.generateReceipt(profile, receipt,
//         themeIndex: 2); // Blue
//     File('test_receipt.pdf').writeAsBytesSync(receiptBytes);
//     print('Receipt generated: test_receipt.pdf');
//   } catch (e) {
//     print('Error generating PDF: $e');
//   }
// }
