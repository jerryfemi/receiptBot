import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/documents/document_data.dart';
import 'package:receipt_bot/documents/market/market_document.dart';
import 'package:receipt_bot/documents/signature/signature_document.dart';
import 'package:receipt_bot/documents/studio/studio_document.dart';
import 'package:receipt_bot/documents/till/till_document.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/utils/log.dart';
import 'package:receipt_bot/utils/logo_codec.dart';

/// Layout numbers as stored in Firestore (`layoutIndex`).
abstract class DocumentLayout {
  static const till = 0;
  static const signature = 1;
  static const market = 2;
  static const studio = 3;
}

/// Simple LRU cache with max size eviction.
class _LruCache<K, V> {
  _LruCache({required this.maxSize});

  final int maxSize;
  final Map<K, V> _cache = {};
  final List<K> _accessOrder = [];

  V? get(K key) {
    if (!_cache.containsKey(key)) return null;
    _accessOrder
      ..remove(key)
      ..add(key);
    return _cache[key];
  }

  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
    } else if (_cache.length >= maxSize) {
      _cache.remove(_accessOrder.removeAt(0));
    }
    _cache[key] = value;
    _accessOrder.add(key);
  }
}

class PdfService {
  static final _LruCache<String, Uint8List> _logoCache = _LruCache(maxSize: 50);

  /// Builds the receipt or invoice PDF in the user's chosen layout.
  ///
  /// Free users always get Studio. Signature takes its accent from the
  /// user's theme; Market, Studio and Till keep their own colours.
  Future<Uint8List> generateReceipt(
    BusinessProfile profile,
    Transaction transaction, {
    int themeIndex = 0,
    int layoutIndex = DocumentLayout.studio,
    Organization? org,
  }) async {
    if (!profile.isPremium) layoutIndex = DocumentLayout.studio;

    final data = DocumentData(
      transaction: transaction,
      currencySymbol: org?.currencySymbol ?? profile.currencySymbol,
      businessName: org?.businessName ?? profile.businessName,
      businessAddress: org?.businessAddress ?? profile.businessAddress,
      businessPhone: org?.displayPhoneNumber ?? profile.displayPhoneNumber,
      bankName: org?.bankName ?? profile.bankName,
      accountNumber: org?.accountNumber ?? profile.accountNumber,
      accountName: org?.accountName ?? profile.accountName,
      logo: await _loadLogo(org?.logoUrl ?? profile.logoUrl),
    );

    final page = switch (layoutIndex) {
      DocumentLayout.till => await buildTillPage(data),
      DocumentLayout.signature =>
        await buildSignaturePage(data, accent: themeAccent(themeIndex)),
      DocumentLayout.market => await buildMarketPage(data),
      _ => await buildStudioPage(data),
    };

    final pdf = pw.Document()..addPage(page);
    return pdf.save();
  }

  /// The accent colour of each theme the user can pick in settings.
  static PdfColor themeAccent(int themeIndex) {
    const accents = [
      '#1E40AF', // 0 Ocean Blue
      '#8B5A2B', // 1 Sand Beige
      '#0F172A', // 2 Midnight Navy
      '#4A5D23', // 3 Sage Green
      '#18181B', // 4 Charcoal Onyx
      '#722F37', // 5 Deep Burgundy
    ];
    return themeIndex >= 0 && themeIndex < accents.length
        ? PdfColor.fromHex(accents[themeIndex])
        : PdfColor.fromHex(accents[5]);
  }

  /// Loads the logo from a data URI (how logos are stored now), a URL, or a
  /// local file, with an in-memory cache. A broken logo never stops the PDF.
  Future<pw.MemoryImage?> _loadLogo(String? source) async {
    if (source == null || source.isEmpty) return null;

    final cached = _logoCache.get(source);
    if (cached != null) return pw.MemoryImage(cached);

    try {
      Uint8List? bytes;
      if (LogoCodec.isDataUri(source)) {
        bytes = LogoCodec.decode(source);
      } else if (source.startsWith('http')) {
        final response = await http
            .get(Uri.parse(source))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) bytes = response.bodyBytes;
      } else {
        bytes = await File(source).readAsBytes();
      }
      if (bytes == null) return null;
      _logoCache.put(source, bytes);
      return pw.MemoryImage(bytes);
    } catch (e) {
      Log.error('pdf', 'Error loading logo: $e');
      return null;
    }
  }
}
