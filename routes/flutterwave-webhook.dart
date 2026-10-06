import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/flutterwave_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/constants.dart';
import 'webhook.dart' as webhook_handler;

final String _projectId =
    Platform.environment['GOOGLE_PROJECT_ID'] ?? 'invoicemaker-b3876';
final String _flutterwaveWebhookSecretHash =
    Platform.environment['FLW_WEBHOOK_SECRET_HASH'] ?? '';

final _firestoreService = FirestoreService(projectId: _projectId);
final _flutterwaveService = FlutterwaveService();
final _whatsappService = WhatsAppService();
bool _servicesInitialized = false;

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;

  if (request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final signature = request.headers['verif-hash'];
  if (_flutterwaveWebhookSecretHash.isEmpty) {
    print('WARNING: FLW_WEBHOOK_SECRET_HASH is missing.');
    return Response(statusCode: 500, body: 'Webhook secret not configured');
  }

  if (signature == null || signature != _flutterwaveWebhookSecretHash) {
    print('WARNING: Flutterwave webhook signature mismatch!');
    return Response(statusCode: 401, body: 'Invalid signature');
  }

  final bodyString = await request.body();

  print('--- FLUTTERWAVE WEBHOOK PAYLOAD ---');
  print(bodyString);
  print('-----------------------------------');

  final payload = jsonDecode(bodyString) as Map<String, dynamic>;

  // Flutterwave can send payloads nested under 'data' or as a flat JSON object
  final event =
      payload['event']?.toString() ?? payload['event.type']?.toString() ?? '';
  final data = (payload['data'] as Map<String, dynamic>?) ?? payload;

  print('Flutterwave Webhook Event/Status: $event / ${data['status']}');

  final status = data['status']?.toString().toLowerCase() ?? '';
  final isCompleted = event == 'charge.completed' || status == 'successful';

  if (isCompleted) {
    final rawTransactionId = data['id'];
    final transactionId = rawTransactionId is num
        ? rawTransactionId.toInt()
        : int.tryParse(rawTransactionId?.toString() ?? '');

    // Support both tx_ref and txRef formats
    final payloadTxRef =
        (data['tx_ref'] ?? data['txRef'])?.toString().trim() ?? '';

    print('Parsed Transaction ID: $transactionId, txRef: $payloadTxRef');

    if (transactionId == null) {
      print('WARNING: Flutterwave transaction ID is null. Skipping.');
      return Response(statusCode: 200);
    }

    try {
      if (!_servicesInitialized) {
        await _firestoreService.initialize();
        // Also ensure WhatsApp webhook services are initialized because
        // generateAndSendSubscriptionReceipt relies on them.
        await webhook_handler.initializeServicesForExternalWebhooks();
        _servicesInitialized = true;
      }

      // Fast duplicate guard before making verify API calls.
      if (payloadTxRef.isNotEmpty &&
          await _firestoreService.isWebhookProcessed(payloadTxRef)) {
        print(
            'Webhook already processed for tx_ref: $payloadTxRef. Skipping verify call.');
        return Response(statusCode: 200);
      }

      final verifyData =
          await _flutterwaveService.verifyTransaction(transactionId);

      final paymentStatus = verifyData['status']?.toString() ?? '';
      final txRef =
          (verifyData['tx_ref']?.toString().trim().isNotEmpty ?? false)
              ? verifyData['tx_ref'].toString().trim()
              : payloadTxRef;
      final amount = (verifyData['amount'] as num?) ?? 0;
      final paymentCurrency =
          verifyData['currency']?.toString().toUpperCase() ?? '';

      if (txRef.isEmpty) {
        print(
            'Flutterwave verify missing tx_ref for transaction: $transactionId');
        return Response(statusCode: 200);
      }

      if (await _firestoreService.isWebhookProcessed(txRef)) {
        print('Webhook already processed for tx_ref: $txRef. Skipping.');
        return Response(statusCode: 200);
      }

      if (paymentStatus.toLowerCase() != 'successful') {
        print('Flutterwave transaction not successful for tx_ref: $txRef');
        return Response(statusCode: 200);
      }

      final phoneNumber =
          await _firestoreService.findUserByPaymentReference(txRef);

      if (phoneNumber == null) {
        print('No user found for Flutterwave tx_ref: $txRef');
        return Response(statusCode: 200);
      }

      final profile = await _firestoreService.getProfile(phoneNumber);
      if (profile == null) {
        print('Profile not found for Flutterwave tx_ref: $txRef');
        return Response(statusCode: 200);
      }

      final selectedTier =
          (profile.pendingSubscriptionTier ?? 'monthly').toLowerCase();
      final bool isAnnual =
          selectedTier == 'yearly' || selectedTier == 'annual';
      final daysToAdd = isAnnual ? 365 : 30;
      final planName = isAnnual ? 'Annual' : 'Monthly';
      final expectedAmount = isAnnual
          ? Pricing.annualUsd.toDouble()
          : Pricing.monthlyUsd.toDouble();
      // Flutterwave checkout for this flow is generated in USD.
      const expectedCurrency = 'USD';

      final isAmountValid = (amount - expectedAmount).abs() <= 0.01;
      final isCurrencyValid = paymentCurrency == expectedCurrency;

      if (!isAmountValid || !isCurrencyValid) {
        print(
            'Flutterwave amount/currency mismatch for tx_ref: $txRef. Expected $expectedAmount $expectedCurrency, got $amount $paymentCurrency');
        await _firestoreService.markWebhookProcessed(
            txRef, 'flutterwave_mismatch');
        await _whatsappService.sendMessage(
          phoneNumber,
          '⚠️ Payment received, but amount/currency did not match your selected plan. Please contact support so we can confirm and apply your upgrade.',
        );
        return Response(statusCode: 200);
      }

      final now = DateTime.now();
      DateTime newExpiryDate;

      if (profile.isPremium && profile.premiumExpiresAt != null) {
        final currentExpiry = profile.premiumExpiresAt!;
        if (currentExpiry.isAfter(now)) {
          newExpiryDate = currentExpiry.add(Duration(days: daysToAdd));
        } else {
          newExpiryDate = now.add(Duration(days: daysToAdd));
        }
      } else {
        newExpiryDate = now.add(Duration(days: daysToAdd));
      }

      await _firestoreService.updateProfileData(phoneNumber, {
        'isPremium': true,
        'pendingSubscriptionTier': planName,
        'premiumExpiresAt': newExpiryDate.toIso8601String(),
        'pendingPaymentReference': '',
        'receiptCount': 0,
      });

      await _firestoreService.markWebhookProcessed(txRef, 'flutterwave');

      await _whatsappService.sendMessage(
        phoneNumber,
        "🎉 **$planName Payment Successful!** 🎉\n\nYou are now a Premium user! Enjoy advanced layouts, monthly sales stats, and more!\n\nYour access is valid until ${newExpiryDate.day}/${newExpiryDate.month}/${newExpiryDate.year}.",
      );

      await webhook_handler.generateAndSendSubscriptionReceipt(
        phoneNumber,
        profile,
        planName,
        // Flutterwave verify `amount` is already in major currency units.
        amount,
        paymentCurrency.isEmpty ? expectedCurrency : paymentCurrency,
      );
    } catch (e, stackTrace) {
      print('Flutterwave verify error: $e\n$stackTrace');
    }
  }

  return Response(statusCode: 200);
}
