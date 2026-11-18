import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/utils/country_utils.dart';

/// Everything a receipt or invoice layout needs, worked out once.
///
/// Layouts only read from this: they never touch the profile, the
/// organisation or Firestore, which keeps each layout file about drawing.
class DocumentData {
  DocumentData({
    required this.transaction,
    required this.currencySymbol,
    this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.bankName,
    this.accountNumber,
    this.accountName,
    this.logo,
  });

  final Transaction transaction;
  final String currencySymbol;
  final String? businessName;
  final String? businessAddress;
  final String? businessPhone;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;
  final pw.MemoryImage? logo;

  static const Set<String> _placeholderNames = {
    '',
    'customer',
    'valued customer',
    'unknown',
    'n/a',
    'client',
  };

  bool get isInvoice => transaction.type == TransactionType.invoice;

  String get title => isInvoice ? 'Invoice' : 'Receipt';

  String get name => (businessName?.trim().isNotEmpty ?? false)
      ? businessName!.trim()
      : 'Your Business';

  /// First letter of the business name, for monograms when there's no logo.
  String get initial => name.characters.first.toUpperCase();

  /// "14 Allen Avenue, Ikeja · 0803 456 7890", skipping missing parts.
  String get contactLine => [businessAddress, businessPhone]
      .where((part) => part != null && part.trim().isNotEmpty)
      .map((part) => part!.trim())
      .join(' · ');

  /// The customer's name, or null when Gemini only filled in a placeholder.
  String? get customerName {
    final value = transaction.customerName.trim();
    return _placeholderNames.contains(value.toLowerCase()) ? null : value;
  }

  /// A short, stable reference such as R-48213 or INV-48213.
  String get number => '${isInvoice ? 'INV' : 'R'}-$serial';

  /// The five digits of [number] on their own, e.g. 48213.
  String get serial {
    final id = (transaction.date.millisecondsSinceEpoch ~/ 1000) % 100000;
    return id.toString().padLeft(5, '0');
  }

  bool get hasBankDetails =>
      (bankName?.isNotEmpty ?? false) && (accountNumber?.isNotEmpty ?? false);

  // --- Money --------------------------------------------------------------

  double get subtotal => transaction.subTotal;
  double get discount => transaction.discount ?? 0;
  double get tax => transaction.tax ?? 0;
  double get total => transaction.transactionTotal;

  String money(double amount) => formatCurrency(amount, currencySymbol);

  /// "NGN" for ₦ and so on; falls back to the symbol for anything unknown.
  String get currencyCode {
    const codes = {
      '₦': 'NGN',
      r'$': 'USD',
      '£': 'GBP',
      '€': 'EUR',
      '₵': 'GHS',
      'GH₵': 'GHS',
      'KSh': 'KES',
      'R': 'ZAR',
    };
    return codes[currencySymbol.trim()] ?? currencySymbol.trim();
  }

  /// An amount without the currency symbol, for columns headed "AMOUNT ₦".
  static String plain(double amount) {
    final text = amount % 1 == 0
        ? amount.toInt().toString()
        : amount.toStringAsFixed(2);
    return text.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  // --- Dates --------------------------------------------------------------

  DateTime get date => transaction.date;
  DateTime? get dueDate => transaction.dueDate;

  /// "18/11/2026"
  static String slashDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  /// "18 Nov 2026"
  static String shortDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// "18th November, 2026"
  static String longDate(DateTime d) =>
      '${_ordinal(d.day)} ${DateFormat('MMMM, yyyy').format(d)}';

  /// "18 · XI · 26", the style used on seals and stamps.
  static String romanDate(DateTime d) {
    const months = [
      'I', 'II', 'III', 'IV', 'V', 'VI', //
      'VII', 'VIII', 'IX', 'X', 'XI', 'XII',
    ];
    final year = (d.year % 100).toString().padLeft(2, '0');
    return '${d.day} · ${months[d.month - 1]} · $year';
  }

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }
}

extension on String {
  /// The string's user-visible characters (handles accents like "É").
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
