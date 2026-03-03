import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:receipt_bot/models/models.dart';

/// Service to interact with Google Gemini API for receipt parsing.
class GeminiService {
  /// The API key for accessing Gemini.
  final String apiKey;
  late final GenerativeModel _model;

  /// Creates a [GeminiService] with the given [apiKey].
  GeminiService({String? apiKey})
      : apiKey = apiKey ?? Platform.environment['GEMINI_API_KEY'] ?? '' {
    if (this.apiKey.isEmpty) {
      print('Warning: GEMINI_API_KEY is missing.');
    }
    _model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: this.apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  /// Parses the given [text] into a [Transaction] using Gemini.
  Future<Transaction> parseTransaction(
    String text, {
    String currencySymbol = '₦',
    String currencyCode = 'NGN',
  }) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final prompt = '''
    You are an expert receipt and invoice parser. The user's currency is $currencyCode ($currencySymbol).
    COnvert any amount to $currencyCode.
    
    Extract the following details from the text:
    - customerName (String): The name of the buyer. If unknown, use "Customer".
    - customerAddress (String?): The buyer's address if mentioned.
    - customerPhone (String?): The buyer's phone number if mentioned.
    - items (List): List of items purchased. Each item needs:
    - description (String)
    - amount (double): The UNIT PRICE for ONE single item.
    - quantity (int): Default to 1 if not specified.
    - totalAmount (double): The sum of all items. Calculate it carefully.
    - amountInWords (String): The total amount written in words (e.g. "One Thousand Two Hundred $currencyCode Only").
    - date (String): The date of the transaction in ISO 8601 format. If not specified, default to today's date: $today.
    - type (String): "invoice" if the user mentions "invoice", "due date", "bank name", "account number", or asks for payment later. "receipt" otherwise.
    - dueDate (String?): If it is an invoice, extract the due date in ISO 8601. Default to 14 days from today if not specified.
    - bankName (String?): If mentioned, the bank name for payment.
    - accountNumber (String?): If mentioned, the account number.
    - accountName (String?): If mentioned, the account name.

### **CRITICAL MATH RULES (READ CAREFULLY)**
    1. **Unit Price vs Total:** - If the user says: "3 items at 5k each", the `amount` (Unit Price) is 5000.
       - If the user says: "3 items for 15k total", calculate the unit price: 15000 / 3 = 5000.
       - **DO NOT** put the Total Price in the `amount` field. `amount` is ALWAYS the price for ONE item.
    
    2. **Calculations:**
       - Always calculate `totalAmount` = Sum of all (Quantity * Unit Price).
       - If Tax/VAT is mentioned, calculate it and add to the total.


    Handle Nigerian currency terms:
    - "k" = 1,000 (e.g., 5k = 5000).
    - "m" = 1,000,000 (e.g., 1.2m = 1,200,000).
    - "m" = 1,000,000 (e.g., 1.2m = 1,200,000).
    - "$currencySymbol", "$currencyCode" are currency symbols to ignore when parsing amounts, but use them to identify values.


    CRITIAL INSTRUCTION:
    - If the user input does not contain any specific items with prices, return an empty list `[]` for "items".
    - Do NOT invent or guess items.
    - If no Customer Name is found, use "Customer".
    - If the user mentions "Tax", "VAT", or similar, extract the amount or calculate it if a percentage is given.
    - If Tax is present, ensure `totalAmount` includes it.

    Return ONLY valid JSON matching this schema:
    {
      "customerName": "String",
      "customerAddress": "String or null",
      "customerPhone": "String or null",
      "items": [
        {"description": "String", "amount": 0.0, "quantity": 1}
      ],
      "tax": 0.0,
      "totalAmount": 0.0,
      "amountInWords": "String",
      "date": "ISO8601_Date_String",
      "type": "receipt" or "invoice",
      "dueDate": "ISO8601_Date_String or null",
      "bankName": "String or null",
      "accountNumber": "String or null",
      "accountName": "String or null"
    }

    User Input: "$text"
    ''';

    const maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        final content = [Content.text(prompt)];
        final response = await _model.generateContent(content);

        if (response.text == null) {
          throw Exception('Gemini returned an empty response.');
        }
        return _cleanAndParseJson(response.text!);
      } catch (e) {
        retryCount++;
        final errorString = e.toString();

        // Check if it's a 503 or 429 error
        if (errorString.contains('503') || errorString.contains('429')) {
          print(
              'Gemini API Error (503/429). Retry $retryCount of $maxRetries...');
          if (retryCount >= maxRetries) {
            throw Exception(
                'GEMINI_BUSY: Google AI servers are temporarily overloaded. Please wait a minute and try again.');
          }
          await Future<void>.delayed(
              Duration(seconds: 2 * retryCount)); // Exponential backoff
        } else {
          // If it's another type of error, don't retry, just throw
          print('Gemini Service Error: $e');
          rethrow;
        }
      }
    }
    throw Exception('Failed to generate content after retries.');
  }

  /// Parses an image (receipt/invoice/handwritten note) into a [Transaction].
  Future<Transaction> parseImageTransaction(
    Uint8List imageBytes, {
    String currencySymbol = '₦',
    String currencyCode = 'NGN',
  }) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final prompt = TextPart('''
      You are an expert receipt parser.
      Look at this image of a receipt, invoice, or handwritten note.
      Extract the transaction details.
      
      RULES:
      1. Default currency is $currencyCode ($currencySymbol).
      2. If you see a total, use it. If not, sum the items.
      3. If you see a date, use it. If not, default to today's date: $today.
      4. If items are listed without total, calculate the total.
      5. Determine "type": "invoice" if the image contains "Invoice" or "Bank Name", "Bill To", or has a Due Date. "receipt" otherwise.
      6. CRITICAL: For `items`, ensure `amount` is the UNIT PRICE.
      
      Return ONLY valid JSON matching this schema:
      {
        "customerName": "String (default: 'Valued Customer')",
        "items": [
          {"description": "String", "amount": 0.0, "quantity": 1}
        ],
        "totalAmount": 0.0,
        "type": "receipt" or "invoice", 
        "dueDate": "String (YYYY-MM-DD) or null",
        "tax": 0.0,
        "amountInWords": "String",
        "date": "ISO8601_Date_String",
        "bankName": "String or null",
        "accountNumber": "String or null",
        "accountName": "String or null"
      }
    ''');

    // Send Image + Text to Gemini
    final imagePart = DataPart('image/jpeg', imageBytes);
    final content = [
      Content.multi([prompt, imagePart])
    ];

    const maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        final response = await _model.generateContent(content);
        if (response.text == null) {
          throw Exception('Gemini returned an empty response for image.');
        }
        return _cleanAndParseJson(response.text!);
      } catch (e) {
        retryCount++;
        final errorString = e.toString();

        if (errorString.contains('503') || errorString.contains('429')) {
          print(
              'Gemini Image API Error (503/429). Retry $retryCount of $maxRetries...');
          if (retryCount >= maxRetries) {
            throw Exception(
                'GEMINI_BUSY: Google AI servers are temporarily overloaded. Please wait a minute and try again.');
          }
          await Future<void>.delayed(Duration(seconds: 2 * retryCount));
        } else {
          print('Gemini Image Parse Error: $e');
          rethrow; // Throw other errors immediately
        }
      }
    }
    throw Exception('Failed to generate image content after retries.');
  }

  // Helper to safely parse Gemini's response
  Transaction _cleanAndParseJson(String rawText) {
    try {
      // Clean up markdown code blocks if present
      final cleanJson =
          rawText.replaceAll('```json', '').replaceAll('```', '').trim();

      final decoded = jsonDecode(cleanJson);
      Map<String, dynamic> json;
      if (decoded is List) {
        if (decoded.isEmpty) throw Exception('Empty list returned from Gemini');
        json = decoded.first as Map<String, dynamic>;
      } else {
        json = decoded as Map<String, dynamic>;
      }

      // Auto-fill date if missing
      if (json['date'] == null || json['date'].toString().isEmpty) {
        json['date'] = DateTime.now().toIso8601String();
      }

      return Transaction.fromJson(json);
    } catch (e) {
      print("Gemini JSON Parse Error: $e \nRaw: $rawText");
      throw Exception("Failed to parse AI response");
    }
  }

  // --- Intent Classification ---
  Future<IntentResult> determineUserIntent(String text) async {
    final prompt = """
    You are Remi, a friendly, professional AI assistant for business owners.
    Analyze the user's message: "$text"
    
    Decide if they are:
    1. Just chatting/greeting (INTENT: chat)
    2. Providing details to make a receipt (INTENT: createReceipt)
    3. Providing details to make an invoice (INTENT: createInvoice)
    4. Asking for help (INTENT: help)
    
    If it's a greeting or general chat, provide a short, friendly,  professional response.
    Return JSON ONLY: {"intent": "chat|createReceipt|createInvoice|help|unknown", "reply": "your friendly response if chat (optional)"}
    """;

    const maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        final response = await _model.generateContent([Content.text(prompt)]);

        if (response.text == null) return IntentResult(UserIntent.unknown);

        // Clean markdown if present
        var cleanText = response.text!.trim();
        if (cleanText.startsWith('```json')) {
          cleanText = cleanText.replaceAll('```json', '').replaceAll('```', '');
        }
        if (cleanText.startsWith('```')) {
          cleanText = cleanText.replaceAll('```', '');
        }

        final decoded = jsonDecode(cleanText) as Map<String, dynamic>;
        final intentString = decoded['intent'] as String?;
        final reply = decoded['reply'] as String?;

        UserIntent intent = UserIntent.unknown;
        if (intentString == 'chat') intent = UserIntent.chat;
        if (intentString == 'createReceipt') intent = UserIntent.createReceipt;
        if (intentString == 'createInvoice') intent = UserIntent.createInvoice;
        if (intentString == 'help') intent = UserIntent.help;

        return IntentResult(intent, response: reply);
      } catch (e) {
        retryCount++;
        final errorString = e.toString();

        if (errorString.contains('503') || errorString.contains('429')) {
          print('Gemini Intent API Error. Retry $retryCount of $maxRetries...');
          if (retryCount >= maxRetries) {
            return IntentResult(
                UserIntent.unknown); // Fallback gracefully if overloaded
          }
          await Future<void>.delayed(Duration(seconds: 2 * retryCount));
        } else {
          print('Gemini Intent Parse Error: $e');
          return IntentResult(UserIntent.unknown);
        }
      }
    }
    return IntentResult(UserIntent.unknown);
  }
}

enum UserIntent { chat, createReceipt, createInvoice, help, unknown }

class IntentResult {
  final UserIntent type;
  final String? response;
  IntentResult(this.type, {this.response});
}
