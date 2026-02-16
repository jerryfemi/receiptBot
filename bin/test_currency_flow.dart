import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/gemini_service.dart';

// Mock values for manual testing
const String _apiKey =
    'AIzaSyDcuu0IKF1plTMAHaOs4y7ipG__EfeWQkc'; // Using the key from webhook.dart for testing

Future<void> main() async {
  final gemini = GeminiService(apiKey: _apiKey);

  print('--- Testing Currency Support ---');

  final testCases = [
    {
      'phone': '+2348012345678', // Nigeria
      'text': 'Bought 2 laptops for 500k each',
      'expectedCurrency': 'NGN',
      'expectedSymbol': '₦',
    },
    {
      'phone': '+15550123456', // USA
      'text': 'Consulting services: 2000',
      'expectedCurrency': 'USD',
      'expectedSymbol': r'$',
    },
    {
      'phone': '+447700900000', // UK
      'text': 'Lunch meeting 50',
      'expectedCurrency': 'GBP',
      'expectedSymbol': '£',
    },
    {
      'phone': '+33612345678', // France (Euro)
      'text': 'Design work 500',
      'expectedCurrency': 'EUR',
      'expectedSymbol': '€',
    },
  ];

  for (final test in testCases) {
    final phone = test['phone'] as String;
    final text = test['text'] as String;
    final expectedCode = test['expectedCurrency'] as String;
    final expectedSymbol = test['expectedSymbol'] as String;

    print('\nTesting for $phone ($expectedCode)...');

    // 1. Test Utility
    final currencyInfo = CountryUtils.getCurrencyFromPhone(phone);
    if (currencyInfo.code != expectedCode) {
      print(
          '❌ CountryUtils Failed: Expected $expectedCode, got ${currencyInfo.code}');
    } else {
      print('✅ CountryUtils Passed');
    }

    // 2. Test Gemini
    try {
      print(
          'Sending to Gemini: "$text" with context $expectedCode ($expectedSymbol)...');
      final transaction = await gemini.parseTransaction(
        text,
        currencyCode: expectedCode,
        currencySymbol: expectedSymbol,
      );

      print(
          'Gemini Response: Items: ${transaction.items.length}, Total: ${transaction.totalAmount}');
      print('Amount in Words: ${transaction.amountInWords}');

      if (transaction.amountInWords?.contains(expectedCode) ?? false) {
        print('✅ Gemini included currency code in words');
      } else {
        print(
            '⚠️ Gemini might have missed currency code in words: ${transaction.amountInWords}');
      }
    } catch (e) {
      print('❌ Gemini Error: $e');
    }
  }
}
