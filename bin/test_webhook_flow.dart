import 'dart:convert';
import 'package:http/http.dart' as http;

const String _serverUrl = 'http://localhost:8080/webhook';

Future<void> main() async {
  print('Running Integration Tests...');

  // Test 1: Simulate New User "Hi"
  await _sendWebhook(
    from: '2348000000001',
    text: 'Hi',
    type: 'text',
  );

  // Test 2: Simulate "Edit Profile" (Menu)
  await _sendWebhook(
    from: '2348000000001',
    text: 'Edit Profile',
    type: 'text',
  );

  // Test 3: Simulate "5" (Edit Address)
  await _sendWebhook(
    from: '2348000000001',
    text: '5',
    type: 'text',
  );

  // Test 4: Simulate Sending Address
  await _sendWebhook(
    from: '2348000000001',
    text: '123 Test Street, Lagos',
    type: 'text',
  );
}

Future<void> _sendWebhook({
  required String from,
  required String text,
  String type = 'text',
}) async {
  print('\nSending: "$text" from $from ($type)...');

  final body = jsonEncode({
    'object': 'whatsapp_business_account',
    'entry': [
      {
        'id': 'WHATSAPP_BUSINESS_ACCOUNT_ID',
        'changes': [
          {
            'value': {
              'messaging_product': 'whatsapp',
              'metadata': {
                'display_phone_number': '1234567890',
                'phone_number_id': '1234567890'
              },
              'contacts': [
                {
                  'profile': {'name': 'Test User'},
                  'wa_id': from
                }
              ],
              'messages': [
                {
                  'from': from,
                  'id': 'wamid.HBgM...',
                  'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
                  'text': {'body': text},
                  'type': type
                }
              ]
            },
            'field': 'messages'
          }
        ]
      }
    ]
  });

  try {
    final response = await http.post(
      Uri.parse(_serverUrl),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    print('Response: ${response.statusCode} ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
