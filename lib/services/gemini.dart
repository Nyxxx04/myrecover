import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_config.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Minimal Google Gemini client (REST generateContent) that always returns
/// JSON matching a schema. Falls through [geminiModels] when a model is
/// overloaded, rate limited or unavailable.
class Gemini {
  static const _retryable = {404, 429, 500, 502, 503, 504};

  static Map<String, dynamic> text(String text) => {'text': text};

  static Map<String, dynamic> image(String base64, [String mimeType = 'image/jpeg']) => {
    'inlineData': {'mimeType': mimeType, 'data': base64},
  };

  static Future<Map<String, dynamic>> json(
    String system,
    List<Map<String, dynamic>> parts,
    Map<String, dynamic> schema,
  ) async {
    if (geminiApiKey.isEmpty || geminiApiKey.startsWith('PASTE')) {
      throw AiException('AI is not set up yet (add your Gemini key in lib/ai_config.dart).');
    }

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [text(system)],
      },
      'contents': [
        {'role': 'user', 'parts': parts},
      ],
      'generationConfig': {'responseMimeType': 'application/json', 'responseJsonSchema': schema},
    });

    for (final model in geminiModels) {
      final http.Response res;
      try {
        res = await http
            .post(
              Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
              headers: {'x-goog-api-key': geminiApiKey, 'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 45));
      } on TimeoutException {
        continue; // try the next model
      } catch (_) {
        throw AiException("Can't reach the AI service. Check your internet connection.");
      }

      if (_retryable.contains(res.statusCode)) continue;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw AiException('AI request failed: ${(data['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}'}');
      }

      final parts = ((data['candidates'] as List?)?.firstOrNull as Map?)?['content']?['parts'] as List? ?? [];
      final out = parts.where((p) => p['thought'] != true).map((p) => p['text'] ?? '').join();
      try {
        return jsonDecode(out) as Map<String, dynamic>;
      } catch (_) {
        continue; // malformed output; try the next model
      }
    }

    throw AiException('The AI service is busy right now. Please try again in a moment.');
  }
}
