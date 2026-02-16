class CountryUtils {
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
