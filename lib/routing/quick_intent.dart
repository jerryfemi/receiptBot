import 'package:receipt_bot/services/gemini_service.dart';

/// Recognises obvious messages without calling Gemini.
///
/// Every Gemini call counts against the free-tier limit, so messages whose
/// meaning is clear from the text alone are handled here:
///   * sales with items and prices ("3 cameras for 500k to John") go straight
///     to receipt parsing, saving one Gemini call per receipt;
///   * simple greetings and thanks get a fixed friendly reply.
///
/// Anything uncertain returns `null`, and the caller asks Gemini as before.
abstract class QuickIntent {
  static IntentResult? detect(String text) {
    final message = text.trim().toLowerCase();
    if (message.isEmpty) return null;

    final greeting = _greetingReply(message);
    if (greeting != null) {
      return IntentResult(UserIntent.chat, response: greeting);
    }

    if (_looksLikeSale(message)) {
      final isInvoice = message.contains('invoice') ||
          RegExp(r'\bdue\b').hasMatch(message);
      return IntentResult(
        isInvoice ? UserIntent.hasInvoiceData : UserIntent.hasReceiptData,
      );
    }

    return null;
  }

  // --- Greetings ---------------------------------------------------------

  static const Map<String, String> _greetings = {
    'hi': "Hi! 👋 Send me the details of a sale and I'll make the receipt, "
        "or type *Menu* to see everything I can do.",
    'hello': "Hello! 👋 Send me the details of a sale and I'll make the "
        "receipt, or type *Menu* to see everything I can do.",
    'hey': "Hey! 👋 Send me the details of a sale and I'll make the receipt, "
        "or type *Menu* to see everything I can do.",
    'good morning': 'Good morning! ☀️ Ready when you are. Send me a sale and '
        "I'll make the receipt.",
    'good afternoon': "Good afternoon! Send me a sale and I'll make the "
        'receipt.',
    'good evening': "Good evening! Send me a sale and I'll make the receipt.",
    'thanks': "You're welcome! 🙌",
    'thank you': "You're welcome! 🙌",
    'ok': '👍',
    'okay': '👍',
  };

  static String? _greetingReply(String message) {
    final cleaned = message.replaceAll(RegExp(r'[!.,\s]+$'), '');
    return _greetings[cleaned];
  }

  // --- Sales ---------------------------------------------------------------

  /// A price: a number with a currency sign or a k/m suffix ("500k", "₦2,500",
  /// "1.5m", "$40"), or a plain number of three to six digits ("15000").
  /// Longer digit runs are left out: they're usually phone or account numbers.
  static final RegExp _price = RegExp(
    r'(?:[₦$£€]\s?\d[\d,]*(?:\.\d+)?)'
    r'|(?:\b\d[\d,]*(?:\.\d+)?\s?(?:k|m|naira|ngn|usd|dollars?)\b)'
    r'|(?:\b\d{1,3}(?:,\d{3})+\b)'
    r'|(?:\b\d{3,6}\b)',
  );

  /// Words that show the user is asking something, not recording a sale.
  static final RegExp _question = RegExp(
    r'^(how|what|when|why|where|who|which|can|could|is|are|do|does|did|'
    r'should|show|tell|check|my|change|update|edit|set)\b'
    r'|\b(stats|statistics|revenue|report|subscription|premium|plan|'
    r'settings|currency|logo|layout|total sales|phone|account|address)\b',
  );

  static bool _looksLikeSale(String message) {
    if (message.contains('?')) return false;
    if (_question.hasMatch(message)) return false;
    if (!_price.hasMatch(message)) return false;

    // Needs at least one word of 3+ letters besides the prices, so an item
    // name is present ("rice", "cameras"), not just a number.
    final words = RegExp('[a-z]{3,}').allMatches(message).length;
    return words >= 1 && message.split(RegExp(r'\s+')).length >= 3;
  }
}
