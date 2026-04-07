import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> syncBookProgress({
    required String fileName,
    required String title,
    required String author,
    required double progress,
    required int totalMinutes,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client.from('library').upsert({
        'user_id': userId,
        'file_name': fileName,
        'title': title,
        'author': author,
        'reading_progress': progress,
        'total_reading_minutes': totalMinutes,
        'last_read': DateTime.now().toIso8601String(),
        'is_new': progress <= 0,
      }, onConflict: 'user_id,file_name');
    } catch (e) {
      debugPrint('Sync error: $e');
    }
  }

  static Future<void> syncReadingSession({
    required String bookTitle,
    required int minutesRead,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      if (minutesRead <= 0) return;

      await _client.from('reading_sessions').insert({
        'user_id': userId,
        'book_title': bookTitle,
        'minutes_read': minutesRead,
        'session_date': DateTime.now().toIso8601String().split('T')[0],
      });
    } catch (e) {
      debugPrint('Session sync error: $e');
    }
  }

  static Future<Map<String, dynamic>> getStats() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return {};

      final response = await _client
          .from('reading_sessions')
          .select('minutes_read')
          .eq('user_id', userId);

      final totalMinutes = (response as List).fold<int>(
          0, (sum, row) => sum + (row['minutes_read'] as int));

      return {'total_minutes': totalMinutes};
    } catch (e) {
      debugPrint('Stats error: $e');
      return {};
    }
  }
}
