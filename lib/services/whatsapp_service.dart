import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Service for WhatsApp Cloud API interactions.
/// Centralizes all WhatsApp messaging with built-in timeout and retry logic.
class WhatsAppService {
  final String token;
  final String phoneNumberId;
  final Duration timeout;
  final int maxRetries;

  static const String _baseUrl = 'https://graph.facebook.com/v17.0';

  WhatsAppService({
    String? token,
    String? phoneNumberId,
    this.timeout = const Duration(seconds: 15),
    this.maxRetries = 1,
  })  : token = token ?? Platform.environment['WHATSAPP_TOKEN'] ?? '',
        phoneNumberId =
            phoneNumberId ?? Platform.environment['PHONE_NUMBER_ID'] ?? '';

  /// Sends a text message with retry logic.
  Future<bool> sendMessage(String to, String message) async {
    final body = jsonEncode({
      'messaging_product': 'whatsapp',
      'to': to,
      'type': 'text',
      'text': {'body': message},
    });

    return _sendRequest('/messages', body);
  }

  /// Sends a document (PDF, etc.) with retry logic.
  Future<bool> sendDocument(
    String to,
    String mediaUrl,
    String filename,
  ) async {
    final body = jsonEncode({
      'messaging_product': 'whatsapp',
      'to': to,
      'type': 'document',
      'document': {
        'link': mediaUrl,
        'filename': filename,
      },
    });

    return _sendRequest('/messages', body);
  }

  /// Sends interactive buttons (max 3 buttons).
  Future<bool> sendInteractiveButtons(
    String to,
    String bodyText,
    List<Map<String, String>> buttons,
  ) async {
    final actionButtons = buttons.map((b) {
      return {
        'type': 'reply',
        'reply': {
          'id': b['id'],
          'title': b['title'],
        }
      };
    }).toList();

    final body = jsonEncode({
      'messaging_product': 'whatsapp',
      'to': to,
      'type': 'interactive',
      'interactive': {
        'type': 'button',
        'body': {'text': bodyText},
        'action': {
          'buttons': actionButtons,
        }
      }
    });

    return _sendRequest('/messages', body);
  }

  /// Sends an interactive list (max 10 items).
  /// Automatically adds a Cancel button if not present and room allows.
  Future<bool> sendInteractiveList(
    String to,
    String bodyText,
    String buttonText,
    String listTitle,
    List<Map<String, String>> rows, {
    bool autoAddCancel = true,
  }) async {
    final listRows = rows.map((r) {
      return {
        'id': r['id'],
        'title': r['title'],
        if (r['description'] != null) 'description': r['description'],
      };
    }).toList();

    // Auto-add Cancel button if not present
    if (autoAddCancel) {
      final hasCancel = listRows.any((r) => r['id'] == 'btn_cancel');
      if (!hasCancel && listRows.length < 10) {
        listRows.add({
          'id': 'btn_cancel',
          'title': 'Cancel',
          'description': 'Exit to main menu'
        });
      }
    }

    final body = jsonEncode({
      'messaging_product': 'whatsapp',
      'to': to,
      'type': 'interactive',
      'interactive': {
        'type': 'list',
        'body': {'text': bodyText},
        'action': {
          'button': buttonText,
          'sections': [
            {
              'title': listTitle,
              'rows': listRows,
            }
          ]
        }
      }
    });

    return _sendRequest('/messages', body);
  }

  /// Sends an image with optional caption.
  Future<bool> sendImage(String to, String mediaUrl, {String? caption}) async {
    final bodyMap = {
      'messaging_product': 'whatsapp',
      'to': to,
      'type': 'image',
      'image': {
        'link': mediaUrl,
      },
    };
    if (caption != null && caption.isNotEmpty) {
      (bodyMap['image'] as Map<String, dynamic>)['caption'] = caption;
    }
    return _sendRequest('/messages', jsonEncode(bodyMap));
  }

  /// Sends an interactive message with media header (image/video/document).
  Future<bool> sendInteractiveMedia(
    String to,
    String mediaUrl,
    String mediaType, {
    required String bodyText,
    required List<Map<String, String>> buttons,
  }) async {
    final actionButtons = buttons.map((b) {
      return {
        'type': 'reply',
        'reply': {
          'id': b['id'],
          'title': b['title'],
        }
      };
    }).toList();

    final body = jsonEncode({
      'messaging_product': 'whatsapp',
      'to': to,
      'type': 'interactive',
      'interactive': {
        'type': 'button',
        'header': {
          'type': mediaType,
          mediaType: {
            'link': mediaUrl,
          }
        },
        'body': {'text': bodyText},
        'action': {
          'buttons': actionButtons,
        }
      }
    });

    return _sendRequest('/messages', body);
  }

  /// Gets the download URL for a media file from its ID.
  Future<String> getMediaUrl(String mediaId) async {
    final url = Uri.parse('$_baseUrl/$mediaId');
    final headers = {'Authorization': 'Bearer $token'};

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.get(url, headers: headers).timeout(timeout);

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          return json['url'] as String;
        }

        if (attempt < maxRetries) {
          await Future<void>.delayed(
              Duration(milliseconds: 200 * (attempt + 1)));
          continue;
        }

        throw Exception('Failed to get media URL: ${response.body}');
      } catch (e) {
        if (attempt >= maxRetries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    throw Exception('Failed to get media URL after $maxRetries retries');
  }

  /// Downloads file bytes from a WhatsApp media URL.
  Future<List<int>> downloadFileBytes(String url) async {
    final headers = {'Authorization': 'Bearer $token'};

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response =
            await http.get(Uri.parse(url), headers: headers).timeout(timeout);

        if (response.statusCode == 200) {
          return response.bodyBytes;
        }

        if (attempt < maxRetries) {
          await Future<void>.delayed(
              Duration(milliseconds: 200 * (attempt + 1)));
          continue;
        }

        throw Exception('Failed to download file: ${response.statusCode}');
      } catch (e) {
        if (attempt >= maxRetries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    throw Exception('Failed to download file after $maxRetries retries');
  }

  /// Internal method for sending requests with retry logic.
  Future<bool> _sendRequest(String endpoint, String body) async {
    final url = Uri.parse('$_baseUrl/$phoneNumberId$endpoint');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response =
            await http.post(url, headers: headers, body: body).timeout(timeout);

        if (response.statusCode == 200) {
          return true;
        }

        print('WhatsApp API error (attempt ${attempt + 1}): ${response.body}');

        if (attempt < maxRetries) {
          await Future<void>.delayed(
              Duration(milliseconds: 200 * (attempt + 1)));
          continue;
        }

        return false;
      } catch (e) {
        print('WhatsApp request error (attempt ${attempt + 1}): $e');
        if (attempt >= maxRetries) return false;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    return false;
  }
}
