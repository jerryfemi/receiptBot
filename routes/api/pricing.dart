import 'package:dart_frog/dart_frog.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/utils/constants.dart';

// In-memory cache variables
int? _cachedPremiumCount;
DateTime? _lastFetchTime;

Future<Response> onRequest(RequestContext context) async {
  // Only allow GET requests
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  try {
    // We get the service from the context dependency injection
    final firestoreService = context.read<FirestoreService>();
    final now = DateTime.now();

    // Only fetch from Firestore if cache is empty or older than 60 seconds
    if (_cachedPremiumCount == null ||
        _lastFetchTime == null ||
        now.difference(_lastFetchTime!).inSeconds > 60) {
      _cachedPremiumCount = await firestoreService.getPremiumUserCount();
      _lastFetchTime = now;
      print("Cache miss: Fetched fresh data from Firestore.");
    } else {
      print("Cache hit: Serving from memory.");
    }

    final spotsLeft = Pricing.earlyAccessMaxUsers - _cachedPremiumCount!;
    final isEarlyAccessActive = spotsLeft > 0;

    final responseData = {
      'isEarlyAccessActive': isEarlyAccessActive,
      'spotsLeft': isEarlyAccessActive ? spotsLeft : 0,
      'monthlyPriceNgn': isEarlyAccessActive
          ? Pricing.earlyAccessMonthlyNgn
          : Pricing.monthlyNgn,
      'annualPriceNgn': isEarlyAccessActive
          ? Pricing.earlyAccessAnnualNgn
          : Pricing.annualNgn,
      'monthlyPriceUsd': Pricing.monthlyUsd,
      'annualPriceUsd': Pricing.annualUsd,
    };

    return Response.json(body: responseData);
  } catch (e) {
    print(r'Error fetching pricing: $e');
    // FAILSAFE: If the database is unreachable, return standard pricing
    return Response.json(
      body: {
        'isEarlyAccessActive': false,
        'spotsLeft': 0,
        'monthlyPriceNgn': Pricing.monthlyNgn,
        'annualPriceNgn': Pricing.annualNgn,
        'monthlyPriceUsd': Pricing.monthlyUsd,
        'annualPriceUsd': Pricing.annualUsd,
      },
    );
  }
}
