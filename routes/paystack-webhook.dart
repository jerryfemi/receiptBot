import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/paystack_service.dart';

final String _whatsappToken = Platform.environment['WHATSAPP_TOKEN'] ?? '';
final String _phoneNumberId = Platform.environment['PHONE_NUMBER_ID'] ?? '';
final String _projectId =
    Platform.environment['GOOGLE_PROJECT_ID'] ?? 'invoicemaker-b3876';
final String _paystackSecretKey =
    Platform.environment['PAYSTACK_SECRET_KEY'] ?? '';

final _firestoreService = FirestoreService(projectId: _projectId);
final _paystackService = PaystackService();
bool _servicesInitialized = false;

Future<void> _sendWhatsAppMessage(String to, String message) async {
  final url =
      Uri.parse('https://graph.facebook.com/v17.0/$_phoneNumberId/messages');
  final headers = {
    'Authorization': 'Bearer $_whatsappToken',
    'Content-Type': 'application/json',
  };
  final body = jsonEncode({
    'messaging_product': 'whatsapp',
    'to': to,
    'type': 'text',
    'text': {'body': message},
  });

  try {
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode != 200) {
      print('Failed to send WhatsApp message: ${response.body}');
    }
  } catch (e) {
    print('Error sending WhatsApp message: $e');
  }
}

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;

  if (request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  // 1. Verify Signature
  final signature = request.headers['x-paystack-signature'];
  if (signature == null) {
    return Response(statusCode: 401, body: 'Missing signature');
  }

  final bodyString = await request.body();
  final hmac = Hmac(sha512, utf8.encode(_paystackSecretKey));
  final digest = hmac.convert(utf8.encode(bodyString));

  if (digest.toString() != signature) {
    print('WARNING: Paystack webhook signature mismatch!');
    return Response(statusCode: 401, body: 'Invalid signature');
  }

  // 2. Parse Event
  final payload = jsonDecode(bodyString);
  final event = payload['event'];

  if (event == 'charge.success') {
    final reference = payload['data']['reference'] as String;

    // 3. The "Ping & Verify" Pattern (Industry Gold Standard)
    // Run the heavy lifting asynchronously to immediately return 200 OK to Paystack
    Future.microtask(() async {
      try {
        if (!_servicesInitialized) {
          await _firestoreService.initialize();
          _servicesInitialized = true;
        }

        print('Ping received for reference: $reference. Verifying...');
        final verifyData = await _paystackService.verifyTransaction(reference);

        final status = verifyData['status'];
        final amountInKobo = verifyData['amount'] as num;
        final email = verifyData['customer']['email'];

        // We expect either 350,000 NGN kobo (3,500 NGN Monthly) or 3,500,000 NGN kobo (35,000 NGN Yearly)
        if (status == 'success' && amountInKobo >= 350000) {
          print('Payment Verified for $email. Upgrading profile...');

          // Find user by pending reference
          final phoneNumber =
              await _firestoreService.findUserByPaymentReference(reference);

          if (phoneNumber != null) {
            // Fetch the user's current profile to do the "fair extension" math
            final profile = await _firestoreService.getProfile(phoneNumber);
            if (profile == null) {
              print('Error: Profile not found for phone: $phoneNumber');
              return;
            }
            final bool isCurrentlyPremium = profile.isPremium;

            DateTime newExpiryDate;
            final now = DateTime.now();
            final daysToAdd =
                amountInKobo >= 3500000 ? 365 : 30; // 35k NGN = Yearly
            final planName = daysToAdd == 365 ? "Annual" : "Monthly";

            if (isCurrentlyPremium && profile.premiumExpiresAt != null) {
              final currentExpiry = profile.premiumExpiresAt!;
              // If current expiry is in the future, add to it. Otherwise, add to today.
              if (currentExpiry.isAfter(now)) {
                newExpiryDate = currentExpiry.add(Duration(days: daysToAdd));
              } else {
                newExpiryDate = now.add(Duration(days: daysToAdd));
              }
            } else {
              newExpiryDate = now.add(Duration(days: daysToAdd));
            }

            // Grant Premium
            await _firestoreService.updateProfileData(phoneNumber, {
              'isPremium': true,
              'pendingSubscriptionTier': planName,
              'premiumExpiresAt': newExpiryDate.toIso8601String(),
              'pendingPaymentReference': '', // Clear it
            });

            await _sendWhatsAppMessage(phoneNumber,
                "🎉 **$planName Payment Successful!** 🎉\n\nYou are now a Premium user! Enjoy advanced layouts, monthly sales stats, and more!\n\nYour access is valid until ${newExpiryDate.day}/${newExpiryDate.month}/${newExpiryDate.year}.");
          } else {
            print('Error: User not found for reference: $reference');
          }
        } else if (status == 'success') {
          print(
              'Payment Verified but amount is insufficient: $amountInKobo kobo. Email: $email');
          final phoneNumber =
              await _firestoreService.findUserByPaymentReference(reference);
          if (phoneNumber != null) {
            final amountNgn = amountInKobo / 100;
            await _sendWhatsAppMessage(phoneNumber,
                "⚠️ **Partial Payment Received** ⚠️\n\nWe received a payment of ₦$amountNgn, which does not exactly match our Monthly (₦3,500) or Annual (₦35,000) plans. Please contact support to have your account manually credited.");
          }
        }
      } catch (e) {
        print('Webhook async verification error: $e');
      }
    });
  }

  return Response(statusCode: 200);
}
