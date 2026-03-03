import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:receipt_bot/services/firestore_service.dart';
import 'webhook.dart' as webhook_handler;

final String _whatsappToken = Platform.environment['WHATSAPP_TOKEN'] ?? '';
final String _phoneNumberId = Platform.environment['PHONE_NUMBER_ID'] ?? '';
final String _projectId =
    Platform.environment['GOOGLE_PROJECT_ID'] ?? 'invoicemaker-b3876';
final String _lsWebhookSecret = Platform.environment['LS_WEBHOOK_SECRET'] ?? '';

final _firestoreService = FirestoreService(projectId: _projectId);
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

  // 1. Verify Signature (Lemon Squeezy uses X-Signature and HMAC SHA256)
  final signature = request.headers['x-signature'];
  if (signature == null) {
    return Response(statusCode: 401, body: 'Missing signature');
  }

  final bodyString = await request.body();
  final hmac = Hmac(sha256, utf8.encode(_lsWebhookSecret));
  final digest = hmac.convert(utf8.encode(bodyString));

  if (digest.toString() != signature) {
    print('WARNING: Lemon Squeezy webhook signature mismatch!');
    return Response(statusCode: 401, body: 'Invalid signature');
  }

  // 2. Parse Event
  final payload = jsonDecode(bodyString);
  final eventName = payload['meta']['event_name'];
  final customData = payload['meta']['custom_data'] as Map<String, dynamic>? ??
      <String, dynamic>{};
  final phoneNumber = customData['phoneNumber'] as String?;
  final planName = customData['planName'] as String?; // "Monthly" or "Annual"

  if (phoneNumber == null) {
    print(
        'WARNING: Webhook received without phoneNumber in custom_data. Cannot upgrade user.');
    return Response(statusCode: 200); // Acknowledge receipt to avoid retries
  }

  // Run heavy lifting asynchronously
  Future.microtask(() async {
    try {
      if (!_servicesInitialized) {
        await _firestoreService.initialize();
        _servicesInitialized = true;
      }

      print('Processing LS Webhook Event: $eventName for $phoneNumber');

      // Fetch the user's current profile to do date math
      final profile = await _firestoreService.getProfile(phoneNumber);
      if (profile == null) {
        print('Error: Profile not found for phone: $phoneNumber');
        return;
      }

      final now = DateTime.now();
      final daysToAdd = planName == 'Annual' ? 365 : 30;

      if (eventName == 'subscription_created' ||
          eventName == 'subscription_payment_success') {
        DateTime newExpiryDate;
        final isCurrentlyPremium = profile.isPremium;

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

        // Grant/Extend Premium
        await _firestoreService.updateProfileData(phoneNumber, {
          'isPremium': true,
          'pendingSubscriptionTier': planName ?? 'Monthly',
          'premiumExpiresAt': newExpiryDate.toIso8601String(),
          'receiptCount': 0, // Reset count on upgrade/renewal
        });

        if (eventName == 'subscription_created') {
          await _sendWhatsAppMessage(phoneNumber,
              "🎉 **Premium Activated!** 🎉\n\nYou are now a Global Premium user! Enjoy advanced layouts, monthly sales stats, and more!\n\nYour access is valid until ${newExpiryDate.day}/${newExpiryDate.month}/${newExpiryDate.year}.");
        } else {
          await _sendWhatsAppMessage(phoneNumber,
              "🔄 **Premium Auto-Renewed!**\n\nYour subscription has been successfully renewed. Your access is now valid until ${newExpiryDate.day}/${newExpiryDate.month}/${newExpiryDate.year}.");
        }

        // Generate and send receipt
        // The total amount is usually in `payload['data']['attributes']['total']` (in cents)
        final attributes =
            payload['data']['attributes'] as Map<String, dynamic>?;
        final amountInCents = attributes?['total'] as num? ??
            (planName == 'Annual' ? 20000 : 2000);

        await webhook_handler.generateAndSendSubscriptionReceipt(
          phoneNumber,
          profile,
          planName ?? 'Monthly',
          amountInCents / 100, // Pass standard amount, not cents
          profile.currencyCode,
        );
      } else if (eventName == 'subscription_cancelled') {
        // We do NOT revoke access immediately (Netflix model). Access naturally expires based on `premiumExpiresAt`.
        // We just notify them.
        await _sendWhatsAppMessage(phoneNumber,
            "ℹ️ **Subscription Cancelled**\n\nYour premium subscription has been cancelled and will not auto-renew. You will continue to have Premium access until your current billing period ends.");
      } else {
        print('Received unhandled Lemon Squeezy event: $eventName');
      }
    } catch (e) {
      print('Lemon Squeezy Webhook processing error: $e');
    }
  });

  return Response(statusCode: 200);
}
