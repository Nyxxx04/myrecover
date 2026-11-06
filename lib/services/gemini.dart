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

/// Minimal Gemini client that always returns JSON matching a schema. Gemini
/// models read text and photos, so every request can include images. Falls
/// through [geminiModels] when a model is overloaded, rate limited or unavailable.
class Gemini {
  static const _retryable = {404, 429, 500, 502, 503, 504};

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

  /// [budget] is how long all models together get. [thinkingLevel] 'minimal'
  /// suits simple extraction; harder judgements (fake reports) use 'low'.
  static Future<Map<String, dynamic>> json(
    String system,
    List<Map<String, dynamic>> parts,
    Map<String, dynamic> schema, {
    Duration budget = const Duration(seconds: 30),
    String thinkingLevel = 'minimal',
  }) async {
    if (geminiApiKey.isEmpty || geminiApiKey.startsWith('PASTE')) {
      throw AiException('AI is not set up yet (add your Gemini key in lib/ai_config.dart).');
    }
    return await _askGemini(system, parts, schema, DateTime.now().add(budget), thinkingLevel) ??
        (throw AiException('The AI service is busy right now. Please try again in a moment.'));
  }

  /// Null when Gemini can't answer in time. Only rejects on a request error
  /// that another model wouldn't fix.
  static Future<Map<String, dynamic>?> _askGemini(
    String system,
    List<Map<String, dynamic>> parts,
    Map<String, dynamic> schema,
    DateTime deadline,
    String thinkingLevel,
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
        // Long "thinking" only adds delay, so keep it to what the task needs.
        if (thinking) 'thinkingConfig': {'thinkingLevel': thinkingLevel},
      },
    });

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
        // Same model again, without thinkingConfig.
        return _askGemini(system, parts, schema, deadline, thinkingLevel);
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
}
