import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One piece of a Gemini request: text, or a file (image, audio) as bytes.
class GeminiPart {
  GeminiPart.text(String text) : _json = {'text': text};

  GeminiPart.data(String mimeType, Uint8List bytes)
      : _json = {
          'inline_data': {
            'mime_type': mimeType,
            'data': base64Encode(bytes),
          },
        };

  final Map<String, dynamic> _json;

  Map<String, dynamic> toJson() => _json;
}

/// The text Gemini returned, or null if it returned nothing.
class GeminiResponse {
  const GeminiResponse(this.text);

  final String? text;
}

/// An error response from the Gemini API.
///
/// [toString] includes the HTTP status code, so callers can spot rate limits
/// (429) and overload (503) by checking for those numbers.
class GeminiApiException implements Exception {
  GeminiApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isRetryable => statusCode == 429 || statusCode == 503;

  @override
  String toString() => 'GeminiApiException($statusCode): $message';
}

/// A small client for Gemini's `generateContent` REST endpoint.
///
/// Replaces the `google_generative_ai` package, which Google no longer
/// maintains. Owning the HTTP call keeps us independent of SDK changes and
/// lets us send any file type Gemini accepts, including voice notes.
class GeminiClient {
  GeminiClient({
    required this.apiKey,
    required this.model,
    this.jsonOutput = true,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _http = httpClient ?? http.Client();

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String apiKey;
  final String model;

  /// Ask Gemini to answer with JSON only.
  final bool jsonOutput;
  final Duration timeout;
  final http.Client _http;

  Future<GeminiResponse> generateContent(List<GeminiPart> parts) async {
    final response = await _http
        .post(
          Uri.parse('$_baseUrl/$model:generateContent'),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': parts.map((part) => part.toJson()).toList(),
              },
            ],
            if (jsonOutput)
              'generationConfig': {'responseMimeType': 'application/json'},
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw GeminiApiException(response.statusCode, _errorMessage(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return GeminiResponse(_extractText(body));
  }

  /// Joins the text of the first candidate's parts.
  static String? _extractText(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;

    final content = (candidates.first as Map<String, dynamic>)['content']
        as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null) return null;

    final text = parts
        .map((part) => (part as Map<String, dynamic>)['text'] as String? ?? '')
        .join();
    return text.isEmpty ? null : text;
  }

  static String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? response.body;
    } catch (_) {
      return response.body;
    }
  }
}
