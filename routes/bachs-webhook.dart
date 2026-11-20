import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:receipt_bot/services/bachs_service.dart';
import 'package:receipt_bot/utils/log.dart';

import 'webhook.dart' as webhook_handler;

final _secret = Platform.environment['BACHS_WEBHOOK_SECRET'] ?? '';
final _bachs = BachsService();

/// Payment notices from Bachs. Only `collection.succeeded` matters: it means
/// a Premium checkout was paid, so the user gets their 30 or 365 days.
Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  if (_secret.isEmpty) {
    Log.error('bachs', 'BACHS_WEBHOOK_SECRET is missing.');
    return Response(statusCode: 500, body: 'Webhook secret not configured');
  }

  // The signature covers the exact bytes Bachs sent, so read them first.
  final rawBody = await request.body();
  final valid = BachsService.verifySignature(
    secret: _secret,
    rawBody: rawBody,
    signatureV2: request.headers['x-bachs-signature-v2'],
    signature: request.headers['x-bachs-signature'],
    timestamp: request.headers['x-bachs-timestamp'],
  );
  if (!valid) {
    Log.error('bachs', 'Webhook signature check failed.');
    return Response(statusCode: 401, body: 'Invalid signature');
  }

  final event = jsonDecode(rawBody) as Map<String, dynamic>;
  if (event['type'] != 'collection.succeeded') return Response();

  final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  final checkoutId = data['checkout_id']?.toString() ?? '';
  if (checkoutId.isEmpty || data['status'] != 'SUCCEEDED') return Response();

  try {
    await webhook_handler.initializeServicesForExternalWebhooks();
    final handler = webhook_handler.subscriptionHandlerForExternalWebhooks();

    // Who paid: the phone we put in the checkout's metadata, or else the
    // user whose pending payment is this checkout.
    final metadata = (data['metadata'] as Map?) ?? const {};
    final phone = metadata['phone']?.toString() ??
        await handler.firestoreService.findUserByPaymentReference(checkoutId);
    if (phone == null) {
      Log.error('bachs', 'No user for checkout $checkoutId');
      return Response();
    }

    // What they bought: decided by the product, not by anything editable.
    final cart = (data['product_cart'] as List?) ?? const [];
    final productId =
        cart.isEmpty ? '' : (cart.first as Map)['product_id']?.toString() ?? '';
    final plan = _bachs.planForProduct(productId);
    if (plan == null) {
      Log.error('bachs', 'Checkout $checkoutId has unknown product $productId');
      return Response();
    }

    await handler.activateBachsPayment(
      checkoutId: checkoutId,
      phone: phone,
      plan: plan,
      amount: num.tryParse('${data['amount']}') ?? 0,
      currency: data['currency']?.toString() ?? '',
    );
  } catch (e, stack) {
    Log.error('bachs', 'Webhook error: $e\n$stack');
    // A 500 makes Bachs retry; a payment already applied is skipped then.
    return Response(statusCode: 500);
  }
  return Response();
}
