import 'dart:convert';
import 'dart:typed_data';

import 'package:receipt_bot/config/app_config.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/gemini_client.dart';
import 'package:receipt_bot/utils/log.dart';

/// Service to interact with Google Gemini API for receipt parsing.
class GeminiService {
  /// The API key for accessing Gemini.
  final String apiKey;
  late final GeminiClient _model;

  /// Creates a [GeminiService] with the given [apiKey].
  GeminiService({String? apiKey})
      : apiKey = apiKey ?? AppConfig.instance.geminiApiKey {
    if (this.apiKey.isEmpty) {
      Log.warn('gemini', 'GEMINI_API_KEY is missing.');
    }
    // Set GEMINI_MODEL in the environment to switch models without a code
    // change when Google retires one.
    _model = GeminiClient(
      apiKey: this.apiKey,
      model: AppConfig.instance.geminiModel,
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
    - discount (double?): If a discount is mentioned, calculate the absolute amount to deduct.
    - notes (String?): Any extra notes or messages for the customer (e.g. "Thank you for your business!").
    - terms (String?): Any terms and conditions (e.g. "No refunds after 7 days").

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
    - If a Discount is present, ensure `totalAmount` has it subtracted.

    Return ONLY valid JSON matching this schema:
    {
      "customerName": "String",
      "customerAddress": "String or null",
      "customerPhone": "String or null",
      "items": [
        {"description": "String", "amount": 0.0, "quantity": 1}
      ],
      "tax": 0.0,
      "discount": 0.0,
      "totalAmount": 0.0,
      "amountInWords": "String",
      "date": "ISO8601_Date_String",
      "type": "receipt" or "invoice",
      "dueDate": "ISO8601_Date_String or null",
      "bankName": "String or null",
      "accountNumber": "String or null",
      "accountName": "String or null",
      "notes": "String or null",
      "terms": "String or null"
    }

    User Input: "$text"
    ''';

    const maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        final content = [GeminiPart.text(prompt)];
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
          Log.warn(
            'gemini',
            'Gemini API Error (503/429). Retry $retryCount of $maxRetries: $e',
          );
          if (retryCount >= maxRetries) {
            throw Exception(
                'GEMINI_BUSY: Google AI servers are temporarily overloaded. Please wait a minute and try again.');
          }
          await Future<void>.delayed(
              Duration(seconds: retryCount)); // 1s, 2s, 3s backoff
        } else {
          // If it's another type of error, don't retry, just throw
          Log.error('gemini', 'Gemini Service Error: $e');
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
    String mimeType = 'image/jpeg',
  }) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final prompt = GeminiPart.text('''
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
        "discount": 0.0,
        "amountInWords": "String",
        "date": "ISO8601_Date_String",
        "bankName": "String or null",
        "accountNumber": "String or null",
        "accountName": "String or null",
        "notes": "String or null",
        "terms": "String or null"
      }
    ''');

    // Send Image/Document + Text to Gemini
    final imagePart = GeminiPart.data(mimeType, imageBytes);
    final content = [prompt, imagePart];

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
          Log.warn(
            'gemini',
            'Gemini Image API Error (503/429). Retry $retryCount of $maxRetries: $e',
          );
          if (retryCount >= maxRetries) {
            throw Exception(
                'GEMINI_BUSY: Google AI servers are temporarily overloaded. Please wait a minute and try again.');
          }
          await Future<void>.delayed(Duration(seconds: retryCount));
        } else {
          Log.error('gemini', 'Gemini Image Parse Error: $e');
          rethrow; // Throw other errors immediately
        }
      }
    }
    throw Exception('Failed to generate image content after retries.');
  }

  // Helper to safely parse Gemini's response
  // --- Voice Notes ---

  /// Parses a WhatsApp voice note describing a sale into a [Transaction].
  ///
  /// Business owners may speak English, Nigerian Pidgin, Yoruba, Igbo or
  /// Hausa, often mixed; Gemini listens to the audio directly.
  Future<Transaction> parseVoiceTransaction(
    Uint8List audioBytes, {
    String mimeType = 'audio/ogg',
    String currencySymbol = '₦',
    String currencyCode = 'NGN',
  }) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final prompt = GeminiPart.text('''
You are an expert receipt assistant for small businesses.
Listen to this voice note. The business owner is describing a sale. They may
speak English, Nigerian Pidgin, Yoruba, Igbo or Hausa, or mix them.

RULES:
1. Default currency is $currencyCode ($currencySymbol).
2. Spoken amounts like "five hundred k", "1.5 million" or "two thousand five
   hundred" are numbers: 500000, 1500000, 2500.
3. For `items`, `amount` is the UNIT PRICE and `quantity` the count.
4. `totalAmount` = sum of quantity × amount, minus discount, plus tax.
5. If they mention an invoice, a due date or bank details, "type" is
   "invoice"; otherwise "receipt".
6. If no customer name is said, use "Customer".
7. Date: use the date they say, otherwise today ($today).
8. If the voice note is not about a sale at all, return {"items": []}.

Return ONLY valid JSON matching this schema:
{
  "customerName": "String",
  "items": [{"description": "String", "amount": 0.0, "quantity": 1}],
  "totalAmount": 0.0,
  "type": "receipt" or "invoice",
  "dueDate": "String (YYYY-MM-DD) or null",
  "tax": 0.0,
  "discount": 0.0,
  "amountInWords": "String",
  "date": "ISO8601_Date_String",
  "bankName": "String or null",
  "accountNumber": "String or null",
  "accountName": "String or null",
  "notes": "String or null",
  "terms": "String or null"
}
''');

    const maxRetries = 3;
    var retryCount = 0;
    while (true) {
      try {
        final response = await _model.generateContent(
          [prompt, GeminiPart.data(mimeType, audioBytes)],
        );
        if (response.text == null) {
          throw Exception('Gemini returned an empty response for audio.');
        }
        return _cleanAndParseJson(response.text!);
      } on GeminiApiException catch (e) {
        retryCount++;
        if (!e.isRetryable) rethrow;
        Log.warn('gemini',
            'Gemini Voice API Error. Retry $retryCount of $maxRetries: $e');
        if (retryCount >= maxRetries) {
          throw Exception(
              'GEMINI_BUSY: Google AI servers are temporarily overloaded. '
              'Please wait a minute and try again.');
        }
        await Future<void>.delayed(Duration(seconds: retryCount));
      }
    }
  }

  // --- Receipt Editing ---

  /// Applies a change the user typed (e.g. "tripod is 300k", "remove the
  /// bag", "customer is John Okafor") to an existing receipt.
  ///
  /// Returns [ReceiptEdit.newSale] when the message is a different sale
  /// rather than a change, so the caller can start a fresh receipt instead.
  Future<ReceiptEdit> applyReceiptEdit(
    Transaction transaction,
    String instruction, {
    String currencySymbol = '₦',
  }) async {
    final current = jsonEncode(transaction.toJson());
    final prompt = """
You edit receipts for a small business. Here is the current receipt as JSON:

$current

The business owner says: "$instruction"

If this message is a change to the receipt above (fix a price, quantity,
item name or customer name, add or remove an item, add a discount, tax or
note), apply ONLY that change and return the full updated receipt as JSON in
exactly the same shape. Keep every field you were not asked to change.
Item "amount" is the unit price, not the line total. Amounts may be written
like 300k (300000), 1.5m (1500000) or 2,500. Currency: $currencySymbol.
Recalculate "totalAmount" as the sum of quantity × amount, minus discount,
plus tax.

If the message is instead a completely new, different sale, return exactly:
{"newSale": true}

Respond with JSON only.
""";

    final response = await _model.generateContent([GeminiPart.text(prompt)]);
    final raw = response.text;
    if (raw == null || raw.trim().isEmpty) {
      throw Exception('Gemini returned an empty response.');
    }

    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic> && decoded['newSale'] == true) {
      return const ReceiptEdit.newSale();
    }
    return ReceiptEdit.updated(_cleanAndParseJson(cleaned));
  }

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
      Log.error('gemini', "Gemini JSON Parse Error: $e \nRaw: $rawText");
      throw Exception("Failed to parse AI response");
    }
  }

  /// Generates a brief business insight based on the provided stats summary.
  Future<String> generateBusinessInsight(String statsSummary) async {
    const fallbackInsight = 'Keep up the great work!';
    final prompt = '''
You are Remi, an AI business assistant for small business owners.
The user requested their sales stats. I am providing you with their raw sales data.

Sales Data:
$statsSummary

Write a VERY BRIEF (1-2 sentences maximum) encouraging business insight or tip based on this data.
Keep it punchy, professional, and directly related to the numbers. Do not include greetings like "Hi" or "Here is your insight". Just the insight. Use minimal emojis (max 1 or 2).
''';

    const maxRetries = 2;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        final content = [GeminiPart.text(prompt)];
        final response = await _model.generateContent(content);

        if (response.text != null && response.text!.isNotEmpty) {
          return response.text!.trim();
        }
        break;
      } catch (e) {
        Log.warn('gemini', 'Gemini insight generation failed: $e');
        retryCount++;
        if (retryCount >= maxRetries) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return fallbackInsight;
  }

  // --- Intent Classification ---
  Future<IntentResult> determineUserIntent(String text) async {
    final prompt = """
You are Remi, a friendly AI receipt/invoice assistant for business owners.

Analyze this message: "$text"

CLASSIFY the intent into ONE of these categories:

1. **chat** - Greetings, thanks, casual conversation, reactions
   Examples: "hello", "thanks!", "wow nice", "good morning", "you're awesome"

2. **help** - Asking how to use the bot or for instructions
   Examples: "how do I use this?", "what can you do?", "help me"

3. **wantsReceipt** - User WANTS to create a receipt but hasn't provided the details yet
   Examples: "I want to create a receipt", "generate receipt", "make a receipt", "I need a receipt", "I sold something today"
   NOTE: If they mention selling but don't include specific items/prices, this is wantsReceipt

4. **wantsInvoice** - User WANTS to create an invoice but hasn't provided the details yet
   Examples: "create invoice", "I need to make an invoice", "generate an invoice for me"

5. **hasReceiptData** - User is PROVIDING actual transaction data (has items + prices)
   Examples: "John bought 3 shirts for 5000 each", "Sold rice 2 bags 15k, beans 3k to Mrs Akin"
   MUST have: at least one item with a price/amount

6. **hasInvoiceData** - User is providing invoice data (items + prices + mentions due date or bank)
   Examples: "Invoice for John: 2 laptops at 500k each, due in 7 days"
   MUST have: items with prices AND mention of "invoice", "due date", or bank details

7. **getStats** - User wants to see their sales performance, revenue, or stats
   Examples: "how many sales have I made?", "show my stats", "what is my revenue for this month?", "stats report"

8. **checkSubscription** - User is asking about their account plan, premium status, or expiry
   Examples: "when does my subscription end?", "am I premium?", "what's my plan?", "check my subscription status"

9. **settings** - User wants to change business details, currency, logo, or layouts
   Examples: "change my business name", "update my currency", "I want to change the layout", "settings", "edit profile"

10. **question** - General questions about the service that aren't stats or subscription related
    Examples: "can I use this in the UK?", "who made this bot?"

11. **unknown** - Cannot determine intent

RESPOND with JSON only:
{
  "intent": "chat|help|wantsReceipt|wantsInvoice|hasReceiptData|hasInvoiceData|getStats|checkSubscription|settings|question|unknown",
  "reply": "Your friendly conversational response (required for chat/question/wantsReceipt/wantsInvoice/getStats/checkSubscription/settings)"
}

RULES:
- For "chat": provide a warm, brief response
- For "getStats": Encourage them as you fetch their data (e.g., "Sure! Let me pull up your performance report for you...")
- For "checkSubscription": Be helpful (e.g., "Let me check your subscription details for you...")
- For "settings": Acknowledge the request (e.g., "Of course, let's update your business settings...")
- For "wantsReceipt": encourage them to share the sale details (customer, items, prices)
- For "wantsInvoice": encourage them to share invoice details
- For "hasReceiptData"/"hasInvoiceData": reply can be empty, we'll parse the data
- If unsure between wantsReceipt and hasReceiptData, check: does it have SPECIFIC items with PRICES? If no → wantsReceipt
""";

    const maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        final response = await _model.generateContent([GeminiPart.text(prompt)]);

        if (response.text == null) return IntentResult(UserIntent.unknown);

        // Clean markdown if present
        var cleanText = response.text!.trim();
        if (cleanText.startsWith('```json')) {
          cleanText = cleanText.replaceAll('```json', '').replaceAll('```', '');
        }
        if (cleanText.startsWith('```')) {
          cleanText = cleanText.replaceAll('```', '');
        }

        final decoded = jsonDecode(cleanText.trim()) as Map<String, dynamic>;
        final intentString = decoded['intent'] as String?;
        final reply = decoded['reply'] as String?;

        UserIntent intent = UserIntent.unknown;
        switch (intentString) {
          case 'chat':
            intent = UserIntent.chat;
            break;
          case 'help':
            intent = UserIntent.help;
            break;
          case 'wantsReceipt':
            intent = UserIntent.wantsReceipt;
            break;
          case 'wantsInvoice':
            intent = UserIntent.wantsInvoice;
            break;
          case 'hasReceiptData':
            intent = UserIntent.hasReceiptData;
            break;
          case 'hasInvoiceData':
            intent = UserIntent.hasInvoiceData;
            break;
          case 'getStats':
            intent = UserIntent.getStats;
            break;
          case 'checkSubscription':
            intent = UserIntent.checkSubscription;
            break;
          case 'settings':
            intent = UserIntent.settings;
            break;
          case 'question':
            intent = UserIntent.question;
            break;
          default:
            intent = UserIntent.unknown;
        }

        return IntentResult(intent, response: reply);
      } catch (e) {
        retryCount++;
        final errorString = e.toString();

        if (errorString.contains('503') || errorString.contains('429')) {
          Log.warn('gemini',
              'Gemini Intent API Error. Retry $retryCount of $maxRetries: $e');
          if (retryCount >= maxRetries) {
            return IntentResult(
                UserIntent.unknown); // Fallback gracefully if overloaded
          }
          await Future<void>.delayed(Duration(seconds: retryCount));
        } else {
          Log.error('gemini', 'Gemini Intent Parse Error: $e');
          return IntentResult(UserIntent.unknown);
        }
      }
    }
    return IntentResult(UserIntent.unknown);
  }
}

enum UserIntent {
  // Casual/conversational
  chat, // Greetings, thanks, casual chatter
  help, // Asking for help/instructions

  // User WANTS to do something (start flow)
  wantsReceipt, // "I want to create a receipt", "generate receipt"
  wantsInvoice, // "I want to create an invoice", "make an invoice"

  // User is PROVIDING data (actual transaction details)
  hasReceiptData, // Contains customer + items + prices
  hasInvoiceData, // Contains client + items + prices + due date/bank

  // Questions about the service
  question, // "When does my subscription end?", "How many receipts?"

  // Business Intelligence
  getStats, // "how many sales have I made?", "show my stats"

  // Account Management
  checkSubscription, // "when does my subscription end?", "am I premium?"
  settings, // "change my business name", "update settings"

  // Fallback
  unknown,
}

/// The result of [GeminiService.applyReceiptEdit].
class ReceiptEdit {
  const ReceiptEdit.updated(Transaction this.transaction) : isNewSale = false;
  const ReceiptEdit.newSale()
      : transaction = null,
        isNewSale = true;

  /// The updated receipt, or null when [isNewSale] is true.
  final Transaction? transaction;

  /// True when the message described a different sale, not a change.
  final bool isNewSale;
}

class IntentResult {
  final UserIntent type;
  final String? response;
  IntentResult(this.type, {this.response});
}
