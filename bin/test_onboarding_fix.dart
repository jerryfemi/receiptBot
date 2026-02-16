import 'dart:convert';
import 'package:http/http.dart' as http;

const String _serverUrl = 'http://localhost:8080/webhook';

Future<void> main() async {
  print('Running Onboarding Fix Verification...');

  // Use a NEW number to ensure new user status
  final String newNumber = '2348999999999';

  // Test 1: Simulate New User "Hi"
  // EXPECTATION: Should NOT show Menu, but ask for Business Name
  await _sendWebhook(
    from: newNumber,
    text: 'Hi',
    type: 'text',
  );

  // Test 2: Simulate Sending "Menu" (Attempt to bypass)
  // EXPECTATION: Should still treat "Menu" as the Business Name (or ask for name again if logic handles it)
  // Current logic: treating text as name.
  // Ideally, if they type "Menu", we might capture it as the name "Menu".
  // But let's just see if we get the "Great! Now address" response, implying it accepted "Hi" as the name?
  // Wait, step 1 sends "Hi". The bot receives "Hi".
  // The bot sees new user. Sends Welcome + "What isn your Business Name?".
  // It does NOT update status to active.

  // So the NEXT message will be treated as the name.
  await _sendWebhook(
    from: newNumber,
    text: 'My Business Name',
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
    // print('Response: ${response.statusCode} ${response.body}');
    print('Response Code: ${response.statusCode}');
  } catch (e) {
    print('Error: $e');
  }
}
