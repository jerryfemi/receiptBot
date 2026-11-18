import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:receipt_bot/config/app_config.dart';
import 'package:receipt_bot/utils/log.dart';

/// Runs once when the server starts, before it accepts any requests.
///
/// Checks the configuration so a missing setting stops the deploy right away
/// with a clear message in the Render logs.
Future<void> init(InternetAddress ip, int port) async {
  final config = AppConfig.instance;
  Log.setLevel(config.logLevel);

  config.validate();

  final optional = config.missingOptional;
  if (optional.isNotEmpty) {
    Log.warn(
      'startup',
      'Optional settings not set (related features are off): '
          '${optional.join(', ')}',
    );
  }
  Log.info('startup', 'Config OK. Gemini model: ${config.geminiModel}');
}

/// Starts the HTTP server. Same as Dart Frog's default.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  return serve(handler, ip, port);
}
