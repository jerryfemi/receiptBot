// import 'dart:convert';

// /// Helper to extract valid JSON from Gemini's potentially markdown-wrapped response.
// Map<String, dynamic> extractJson(String text) {
//   // 1. Try finding a JSON block within markdown code fences
//   final pattern = RegExp(r'```json\s*(\{.*?\})\s*```', dotAll: true);
//   final match = pattern.firstMatch(text);

//   if (match != null) {
//     try {
//       final jsonStr = match.group(1)!;
//       return jsonDecode(jsonStr) as Map<String, dynamic>;
//     } catch (_) {
//       // Fallback if decode fails
//     }
//   }

//   // 2. Try finding just the first { and last } (fallback)
//   try {
//     final start = text.indexOf('{');
//     final end = text.lastIndexOf('}');
//     if (start != -1 && end != -1) {
//       final jsonStr = text.substring(start, end + 1);
//       return jsonDecode(jsonStr) as Map<String, dynamic>;
//     }
//   } catch (_) {}

//   // 3. Return empty if nothing valid user
//   return {};
// }
