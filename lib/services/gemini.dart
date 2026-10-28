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

  /// Models that recently failed (rate limited / overloaded) are skipped until
  /// this time, so each request doesn't wait on them again.
  static final _coolUntil = <String, DateTime>{};

  /// Models that rejected `thinkingConfig`; they are called without it.
  static final _noThinking = <String>{};

  static List<String> _modelOrder() {
    final now = DateTime.now();
    bool cooling(String m) => _coolUntil[m]?.isAfter(now) ?? false;
    return [
      ...geminiModels.where((m) => !cooling(m)),
      ...geminiModels.where(cooling),
    ];
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

  static Map<String, dynamic> image(
    String base64, [
    String mimeType = 'image/jpeg',
  ]) => {
    'inlineData': {'mimeType': mimeType, 'data': base64},
  };

  static Future<Map<String, dynamic>> json(
    String system,
    List<Map<String, dynamic>> parts,
    Map<String, dynamic> schema,
  ) async {
    if (geminiApiKey.isEmpty || geminiApiKey.startsWith('PASTE')) {
      throw AiException(
        'AI is not set up yet (add your Gemini key in lib/ai_config.dart).',
      );
    }

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

    for (final model in _modelOrder()) {
      final thinking = !_noThinking.contains(model);
      final http.Response res;
      try {
        res = await http
            .post(
              Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
              ),
              headers: {
                'x-goog-api-key': geminiApiKey,
                'Content-Type': 'application/json',
              },
              body: body(thinking),
            )
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        _coolDown(model, 504);
        continue; // try the next model
      } catch (_) {
        throw AiException(
          "Can't reach the AI service. Check your internet connection.",
        );
      }

      if (_retryable.contains(res.statusCode)) {
        _coolDown(model, res.statusCode);
        continue;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 400 && thinking && res.body.contains('thinking')) {
        _noThinking.add(model);
        return json(
          system,
          parts,
          schema,
        ); // same model again, without thinkingConfig
      }
      if (res.statusCode >= 400) {
        throw AiException(
          'AI request failed: ${(data['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}'}',
        );
      }

      final outParts =
          ((data['candidates'] as List?)?.firstOrNull
                  as Map?)?['content']?['parts']
              as List? ??
          [];
      final out = outParts
          .where((p) => p['thought'] != true)
          .map((p) => p['text'] ?? '')
          .join();
      try {
        return jsonDecode(out) as Map<String, dynamic>;
      } catch (_) {
        continue; // malformed output; try the next model
      }
    }

    throw AiException(
      'The AI service is busy right now. Please try again in a moment.',
    );
  }
}
