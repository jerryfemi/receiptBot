import 'package:receipt_bot/models/models.dart';

class CountryUtils {
  static const Set<String> forceInternationalGatewayNumbers = {
    '2347026964097',
  };

  /// Returns a tuple of (currencyCode, currencySymbol) based on the phone number.
  /// Defaults to ('USD', '$') if the country code is not recognized.
  static ({String code, String symbol}) getCurrencyFromPhone(
      String phoneNumber) {
    // Remove any non-digit characters except the leading +
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    if (cleanPhone.startsWith('234') || cleanPhone.startsWith('+234')) {
      return (code: 'NGN', symbol: '₦');
    } else if (cleanPhone.startsWith('44') || cleanPhone.startsWith('+44')) {
      return (code: 'GBP', symbol: '£');
    } else if (cleanPhone.startsWith('33') || // France
        cleanPhone.startsWith('+33') ||
        cleanPhone.startsWith('49') || // Germany
        cleanPhone.startsWith('+49') ||
        cleanPhone.startsWith('34') || // Spain
        cleanPhone.startsWith('+34') ||
        cleanPhone.startsWith('39') || // Italy
        cleanPhone.startsWith('+39') ||
        cleanPhone.startsWith('31') || // Netherlands
        cleanPhone.startsWith('+31')) {
      return (code: 'EUR', symbol: '€');
    } else if (cleanPhone.startsWith('91') || cleanPhone.startsWith('+91')) {
      return (code: 'INR', symbol: '₹');
    } else if (cleanPhone.startsWith('27') || cleanPhone.startsWith('+27')) {
      return (code: 'ZAR', symbol: 'R');
    } else if (cleanPhone.startsWith('254') || cleanPhone.startsWith('+254')) {
      return (code: 'KES', symbol: 'KSh');
    } else if (cleanPhone.startsWith('233') || cleanPhone.startsWith('+233')) {
      return (code: 'GHS', symbol: '₵');
    }

    // Default to USD
    return (code: 'USD', symbol: r'$');
  }

  /// Determines if the given phone number belongs to a region supported by Paystack
  /// (Nigeria, Ghana, Kenya, South Africa). Otherwise, it falls back to international billing (Flutterwave).
  static bool isPaystackRegion(String phoneNumber) {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final digitsOnly = cleanPhone.replaceAll(RegExp(r'\D'), '');

    if (forceInternationalGatewayNumbers.contains(digitsOnly)) {
      return false;
    }

    return cleanPhone.startsWith('234') || // Nigeria
        cleanPhone.startsWith('+234') ||
        cleanPhone.startsWith('233') || // Ghana
        cleanPhone.startsWith('+233') ||
        cleanPhone.startsWith('254') || // Kenya
        cleanPhone.startsWith('+254') ||
        cleanPhone.startsWith('27') || // South Africa
        cleanPhone.startsWith('+27') ||
        cleanPhone.startsWith('225') || // Côte d'Ivoire
        cleanPhone.startsWith('+225') ||
        cleanPhone.startsWith('250') || // Rwanda
        cleanPhone.startsWith('+250') ||
        cleanPhone.startsWith('221') || // Senegal
        cleanPhone.startsWith('+221') ||
        cleanPhone.startsWith('256') || // Uganda
        cleanPhone.startsWith('+256') ||
        cleanPhone.startsWith('255') || // Tanzania
        cleanPhone.startsWith('+255') ||
        cleanPhone.startsWith('237') || // Cameroon
        cleanPhone.startsWith('+237') ||
        cleanPhone.startsWith('260') || // Zambia
        cleanPhone.startsWith('+260') ||
        cleanPhone.startsWith('263') || // Zimbabwe
        cleanPhone.startsWith('+263');
  }

  static const List<Map<String, String>> supportedCurrencies = [
    {'code': 'NGN', 'symbol': '₦', 'name': 'Nigerian Naira'},
    {'code': 'USD', 'symbol': r'$', 'name': 'US Dollar'},
    {'code': 'GBP', 'symbol': '£', 'name': 'British Pound'},
    {'code': 'EUR', 'symbol': '€', 'name': 'Euro'},
    {'code': 'KES', 'symbol': 'KSh', 'name': 'Kenyan Shilling'},
    {'code': 'GHS', 'symbol': '₵', 'name': 'Ghanaian Cedi'},
    {'code': 'ZAR', 'symbol': 'R', 'name': 'South African Rand'},
    {'code': 'INR', 'symbol': '₹', 'name': 'Indian Rupee'},
  ];
}

extension TransactionTotal on Transaction {
  double get transactionTotal {
    final double subtotal =
        items.fold(0, (sum, item) => sum + (item.amount * item.quantity));
    return subtotal + (tax ?? 0);
  }
}

String formatCurrency(double amount, String symbol) {
  // Basic comma formatting
  return '$symbol${amount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
}
