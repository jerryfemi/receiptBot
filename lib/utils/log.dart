import 'dart:io';

/// How serious a log line is. Lines below the configured level are skipped.
enum LogLevel { debug, info, warn, error }

/// A small logger with levels and a tag saying which part of the bot wrote it.
///
/// Output looks like:
///   2026-11-18T15:04:05.123Z INFO  [receipt] PDF sent to 2348012345678
///
/// Set LOG_LEVEL=debug in the environment to see debug lines; the default is
/// info. Errors and warnings go to stderr, everything else to stdout.
abstract class Log {
  static LogLevel minLevel = LogLevel.info;

  /// Sets [minLevel] from a name such as `debug` or `warn`.
  static void setLevel(String name) {
    minLevel = LogLevel.values.firstWhere(
      (level) => level.name == name.trim().toLowerCase(),
      orElse: () => LogLevel.info,
    );
  }

  static void debug(String tag, String message) =>
      _write(LogLevel.debug, tag, message);

  static void info(String tag, String message) =>
      _write(LogLevel.info, tag, message);

  static void warn(String tag, String message) =>
      _write(LogLevel.warn, tag, message);

  static void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final details = StringBuffer(message);
    if (error != null) details.write(': $error');
    if (stackTrace != null) details.write('\n$stackTrace');
    _write(LogLevel.error, tag, details.toString());
  }

  static void _write(LogLevel level, String tag, String message) {
    if (level.index < minLevel.index) return;
    final time = DateTime.now().toUtc().toIso8601String();
    final label = level.name.toUpperCase().padRight(5);
    final line = '$time $label [$tag] $message';
    if (level.index >= LogLevel.warn.index) {
      stderr.writeln(line);
    } else {
      stdout.writeln(line);
    }
  }
}
