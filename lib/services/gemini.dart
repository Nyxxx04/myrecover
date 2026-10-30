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

/// Minimal AI client that always returns JSON matching a schema. Gemini answers
/// first, falling through [geminiModels] when a model is overloaded, rate
/// limited or unavailable. If that fails or takes too long, Groq answers.
class Gemini {
  static const _retryable = {404, 429, 500, 502, 503, 504};

  /// How long Gemini gets, across all its models, before Groq takes over.
  static const _geminiBudget = Duration(seconds: 10);

  /// Models that recently failed (rate limited / overloaded) are skipped until
  /// this time, so each request doesn't wait on them again.
  static final _coolUntil = <String, DateTime>{};

  /// Models that rejected `thinkingConfig`; they are called without it.
  static final _noThinking = <String>{};

  static Iterable<String> _availableModels() {
    final now = DateTime.now();
    return geminiModels.where((m) => !(_coolUntil[m]?.isAfter(now) ?? false));
  }

  static void _coolDown(String model, int status) {
    final wait = switch (status) {
      429 => const Duration(minutes: 5),
      404 => const Duration(hours: 1),
      _ => const Duration(minutes: 1),
    };
    _coolUntil[model] = DateTime.now().add(wait);
  }

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
    return await _askGemini(system, parts, schema) ??
        await _askGroq(system, parts, schema) ??
        (throw AiException('The AI service is busy right now. Please try again in a moment.'));
  }

  /// Null when Gemini can't answer in time. Only rejects on a request error
  /// that another model wouldn't fix.
  static Future<Map<String, dynamic>?> _askGemini(
    String system,
    List<Map<String, dynamic>> parts,
    Map<String, dynamic> schema,
  ) async {
    String body(bool thinking) => jsonEncode({
      'systemInstruction': {
        'parts': [text(system)],
      },
      'contents': [
        {'role': 'user', 'parts': parts},
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseJsonSchema': schema,
        // These are simple extraction tasks; long "thinking" only adds delay.
        if (thinking) 'thinkingConfig': {'thinkingLevel': 'minimal'},
      },
    });

    final deadline = DateTime.now().add(_geminiBudget);
    for (final model in _availableModels()) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return null;
      final thinking = !_noThinking.contains(model);
      final http.Response res;
      try {
        res = await http
            .post(
              Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
              headers: {'x-goog-api-key': geminiApiKey, 'Content-Type': 'application/json'},
              body: body(thinking),
            )
            .timeout(remaining);
      } on TimeoutException {
        return null; // slow, not broken: keep the model for next time
      } catch (_) {
        throw AiException("Can't reach the AI service. Check your internet connection.");
      }

      if (_retryable.contains(res.statusCode)) {
        _coolDown(model, res.statusCode);
        continue;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 400 && thinking && res.body.contains('thinking')) {
        _noThinking.add(model);
        return _askGemini(system, parts, schema); // same model again, without thinkingConfig
      }
      if (res.statusCode >= 400) {
        throw AiException('AI request failed: ${(data['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}'}');
      }

      final outParts = ((data['candidates'] as List?)?.firstOrNull as Map?)?['content']?['parts'] as List? ?? [];
      final out = outParts.where((p) => p['thought'] != true).map((p) => p['text'] ?? '').join();
      try {
        return jsonDecode(out) as Map<String, dynamic>;
      } catch (_) {
        continue; // malformed output; try the next model
      }
    }
    return null;
  }

  /// Null when Groq can't answer either.
  static Future<Map<String, dynamic>?> _askGroq(
    String system,
    List<Map<String, dynamic>> parts,
    Map<String, dynamic> schema,
  ) async {
    if (groqApiKey.isEmpty || groqApiKey.startsWith('PASTE')) return null;
    final content = [
      for (final part in parts)
        if (part['inlineData'] case {'mimeType': final mime, 'data': final data})
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mime;base64,$data'},
          }
        else
          {'type': 'text', 'text': part['text']},
    ];
    final required = (schema['required'] as List?)?.cast<String>() ?? const <String>[];
    try {
      final res = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {'Authorization': 'Bearer $groqApiKey', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': groqModel,
              'temperature': 0.2,
              'response_format': {'type': 'json_object'},
              'messages': [
                {'role': 'system', 'content': '$system\n\nReply only with JSON matching this schema:\n${jsonEncode(schema)}'},
                {'role': 'user', 'content': content},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final out = jsonDecode(data['choices'][0]['message']['content'] as String) as Map<String, dynamic>;
      // Groq only promises valid JSON, not the schema.
      return required.every(out.containsKey) ? out : null;
    } catch (_) {
      return null;
    }
  }
}
