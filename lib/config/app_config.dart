import 'dart:io';

/// Every setting the bot reads from its environment, in one place.
///
/// Settings are read once, when [AppConfig.instance] is first used. Call
/// [validate] at startup (see `main.dart`) so a missing or misspelled
/// variable stops the server immediately with a clear message, instead of
/// failing quietly later.
class AppConfig {
  AppConfig._(Map<String, String> env)
      : googleProjectId = _read(env, 'GOOGLE_PROJECT_ID'),
        whatsappToken = _read(env, 'WHATSAPP_TOKEN'),
        phoneNumberId = _read(env, 'PHONE_NUMBER_ID'),
        verifyToken = _read(env, 'VERIFY_TOKEN'),
        metaAppSecret = _read(env, 'META_APP_SECRET'),
        geminiApiKey = _read(env, 'GEMINI_API_KEY'),
        geminiModel = _read(env, 'GEMINI_MODEL', fallback: 'gemini-3.8-flash'),
        publicBaseUrl =
            _read(env, 'PUBLIC_BASE_URL').replaceAll(RegExp(r'/+$'), ''),
        logLevel = _read(env, 'LOG_LEVEL', fallback: 'info'),
        paystackSecretKey = _read(env, 'PAYSTACK_SECRET_KEY'),
        flutterwaveSecretKey = _read(env, 'FLW_SECRET_KEY'),
        flutterwaveRedirectUrl =
            _read(env, 'FLW_REDIRECT_URL', fallback: 'https://wa.me/message'),
        flutterwaveWebhookHash = _read(env, 'FLW_WEBHOOK_SECRET_HASH');

  /// The settings for this server process.
  static final AppConfig instance = AppConfig._(Platform.environment);

  // --- Required: the bot can't work without these ---
  final String googleProjectId;
  final String whatsappToken;
  final String phoneNumberId;
  final String verifyToken;
  final String metaAppSecret;
  final String geminiApiKey;

  // --- Optional: have sensible defaults or only power one feature ---
  final String geminiModel;
  final String publicBaseUrl;
  final String logLevel;
  final String paystackSecretKey;
  final String flutterwaveSecretKey;
  final String flutterwaveRedirectUrl;
  final String flutterwaveWebhookHash;

  /// Names of required settings that are empty or missing.
  List<String> get missingRequired => [
        if (googleProjectId.isEmpty) 'GOOGLE_PROJECT_ID',
        if (whatsappToken.isEmpty) 'WHATSAPP_TOKEN',
        if (phoneNumberId.isEmpty) 'PHONE_NUMBER_ID',
        if (verifyToken.isEmpty) 'VERIFY_TOKEN',
        if (metaAppSecret.isEmpty) 'META_APP_SECRET',
        if (geminiApiKey.isEmpty) 'GEMINI_API_KEY',
      ];

  /// Names of optional settings that are empty, for a startup warning.
  List<String> get missingOptional => [
        if (publicBaseUrl.isEmpty) 'PUBLIC_BASE_URL',
        if (paystackSecretKey.isEmpty) 'PAYSTACK_SECRET_KEY',
        if (flutterwaveSecretKey.isEmpty) 'FLW_SECRET_KEY',
        if (flutterwaveWebhookHash.isEmpty) 'FLW_WEBHOOK_SECRET_HASH',
      ];

  /// Throws a [StateError] naming every missing required setting.
  void validate() {
    final missing = missingRequired;
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required environment variables: ${missing.join(', ')}. '
        'Add them in Render > Environment and redeploy.',
      );
    }
  }

  static String _read(
    Map<String, String> env,
    String key, {
    String fallback = '',
  }) {
    final value = env[key]?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }
}
