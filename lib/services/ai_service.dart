import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiService {
  static const String _defaultKey = 'AIzaSyCpcLw__slRk5H5mUesE4pHsgnenTSQDbU';
  static const String _apiKey = 'AIzaSyCpcLw__slRk5H5mUesE4pHsgnenTSQDbU';

  static GenerativeModel? _model;

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString('gemini_api_key');
      final keyToUse =
          (savedKey != null &&
              savedKey.isNotEmpty &&
              savedKey != 'AIzaSyCpcLw__slRk5H5mUesE4pHsgnenTSQDbU')
          ? savedKey
          : _apiKey;
      if (keyToUse == 'AIzaSyCpcLw__slRk5H5mUesE4pHsgnenTSQDbU') return;
      _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: keyToUse);
    } catch (e) {
      debugPrint('AI init error: $e');
    }
  }

  static bool get isConfigured => _model != null;

  static Future<void> updateApiKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gemini_api_key', key);
      if (key.isNotEmpty && key != _defaultKey) {
        _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: key);
      }
    } catch (e) {
      debugPrint('API key update error: $e');
    }
  }

  // ━━━ DAILY LIMIT TRACKING ━━━

  static Future<bool> canAskQuestion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = DateTime.now().toIso8601String().split('T')[0];
      final count = prefs.getInt('ai_questions_$todayKey') ?? 0;
      return count < 5;
    } catch (_) {
      return true;
    }
  }

  static Future<int> getRemainingQuestions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = DateTime.now().toIso8601String().split('T')[0];
      final count = prefs.getInt('ai_questions_$todayKey') ?? 0;
      return (5 - count).clamp(0, 5);
    } catch (_) {
      return 5;
    }
  }

  static Future<void> incrementQuestionCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = DateTime.now().toIso8601String().split('T')[0];
      final count = prefs.getInt('ai_questions_$todayKey') ?? 0;
      await prefs.setInt('ai_questions_$todayKey', count + 1);
    } catch (_) {}
  }

  // ━━━ AI QUERIES ━━━

  static Future<String> askAboutBook({
    required String bookTitle,
    required String currentChapter,
    required String question,
    bool isPro = false,
  }) async {
    if (!isPro) {
      final canAsk = await canAskQuestion();
      if (!canAsk) return 'DAILY_LIMIT_REACHED';
    }
    if (_model == null) return 'ADD_API_KEY';
    try {
      await incrementQuestionCount();
      final prompt =
          'You are an expert literary companion helping '
          'someone read "$bookTitle". '
          'Current chapter: "$currentChapter". '
          'Answer concisely in 2-3 paragraphs: '
          '$question '
          'Be conversational. Avoid future spoilers.';
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      return response.text ?? 'Could not generate response.';
    } catch (e) {
      return 'ERROR: ${e.toString()}';
    }
  }

  static Future<String> getBookSummary({
    required String bookTitle,
    required String author,
  }) async {
    if (_model == null) return 'Add Gemini API key to enable AI summaries.';

    try {
      final prompt =
          '''
Give me a brief, engaging summary of the book "$bookTitle" by $author in exactly 3 short paragraphs:
1. What the book is about (no spoilers)
2. Why people love it
3. Who should read it
Keep it concise and conversational.
''';
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      return response.text ?? 'Could not generate summary.';
    } catch (e) {
      return 'Could not load summary.';
    }
  }
}
