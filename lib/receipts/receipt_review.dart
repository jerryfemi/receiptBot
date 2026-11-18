import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/utils/country_utils.dart';

/// Decides whether a parsed receipt can be sent straight away or should be
/// shown to the user first, and builds the preview text.
///
/// Remi sends receipts instantly. It only stops to ask when something looks
/// wrong or required details are missing, so mistakes are caught before a
/// customer sees them without slowing down the normal case.
abstract class ReceiptReview {
  /// Placeholder names Gemini uses when no customer was given.
  static const Set<String> _placeholderNames = {
    '',
    'customer',
    'valued customer',
    'unknown',
    'n/a',
    'client',
  };

  /// Returns the problems found, as short lines for the user.
  /// An empty list means the receipt is fine to send.
  static List<String> issues(Transaction transaction, String currencySymbol) {
    final problems = <String>[];

    if (transaction.items.isEmpty) {
      problems.add('No items found');
    }

    for (final item in transaction.items) {
      if (item.amount <= 0) {
        problems.add('No price for *${item.description}*');
      }
      if (item.quantity <= 0) {
        problems.add('No quantity for *${item.description}*');
      }
    }

    // Invoices go to a client who has to pay, so a name is required.
    final isInvoice = transaction.type == TransactionType.invoice;
    if (isInvoice && _isPlaceholderName(transaction.customerName)) {
      problems.add('No client name');
    }

    // Gemini's total should match quantity x price. If it doesn't, either the
    // AI miscounted or the message stated a different total: worth a look.
    final calculated = transaction.transactionTotal;
    final stated = transaction.totalAmount;
    if (stated > 0 && (stated - calculated).abs() > 1) {
      problems.add(
        'The total in your message (${formatCurrency(stated, currencySymbol)}) '
        "doesn't match the items (${formatCurrency(calculated, currencySymbol)})",
      );
    }

    return problems;
  }

  /// A WhatsApp-formatted summary of the receipt, followed by [problems].
  static String preview(
    Transaction transaction,
    String currencySymbol, {
    List<String> problems = const [],
  }) {
    final isInvoice = transaction.type == TransactionType.invoice;
    final document = isInvoice ? 'invoice' : 'receipt';
    final name = _isPlaceholderName(transaction.customerName)
        ? ''
        : ' for *${transaction.customerName}*';

    final lines = StringBuffer()
      ..writeln("Before I make the $document$name, please check this 👇")
      ..writeln();

    for (final item in transaction.items) {
      final price = formatCurrency(item.amount, currencySymbol);
      final lineTotal = formatCurrency(item.amount * item.quantity, currencySymbol);
      lines.writeln('• ${item.quantity} × ${item.description} @ $price = $lineTotal');
    }

    if ((transaction.discount ?? 0) > 0) {
      lines.writeln(
          'Discount: -${formatCurrency(transaction.discount!, currencySymbol)}');
    }
    if ((transaction.tax ?? 0) > 0) {
      lines.writeln('Tax: ${formatCurrency(transaction.tax!, currencySymbol)}');
    }

    lines
      ..writeln()
      ..writeln(
          '*Total: ${formatCurrency(transaction.transactionTotal, currencySymbol)}*');

    if (problems.isNotEmpty) {
      lines
        ..writeln()
        ..writeln('⚠️ ${problems.join('\n⚠️ ')}');
    }

    lines
      ..writeln()
      ..write('Tap *Send* if it looks right, or just tell me what to change '
          "(e.g. _tripod is 300k_).");

    return lines.toString();
  }

  static bool _isPlaceholderName(String name) =>
      _placeholderNames.contains(name.trim().toLowerCase());
}
