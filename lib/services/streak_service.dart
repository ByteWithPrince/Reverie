import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class StreakService {
  static Future<int> getCurrentStreak() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastReadDate = prefs.getString('last_read_date');
      final currentStreak = prefs.getInt('current_streak') ?? 0;

      if (lastReadDate == null) return 0;

      final last = DateTime.parse(lastReadDate);
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      final isToday = last.year == today.year &&
          last.month == today.month &&
          last.day == today.day;

      final isYesterday = last.year == yesterday.year &&
          last.month == yesterday.month &&
          last.day == yesterday.day;

      if (isToday || isYesterday) return currentStreak;

      // Streak broken
      await prefs.setInt('current_streak', 0);
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> recordReadingToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T')[0];
      final lastReadDate = prefs.getString('last_read_date');

      if (lastReadDate == todayStr) return; // Already recorded today

      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayStr = yesterday.toIso8601String().split('T')[0];

      int streak = prefs.getInt('current_streak') ?? 0;

      if (lastReadDate == yesterdayStr) {
        // Consecutive day — increase streak
        streak++;
      } else {
        // New streak starting today
        streak = 1;
      }

      await prefs.setString('last_read_date', todayStr);
      await prefs.setInt('current_streak', streak);
      await prefs.setInt(
        'longest_streak',
        max(streak, prefs.getInt('longest_streak') ?? 0),
      );

      // Track total days
      final totalDays = prefs.getInt('total_days_read') ?? 0;
      await prefs.setInt('total_days_read', totalDays + 1);
    } catch (_) {}
  }

  static Future<Map<String, int>> getAllStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'current_streak': await getCurrentStreak(),
        'longest_streak': prefs.getInt('longest_streak') ?? 0,
        'total_days': prefs.getInt('total_days_read') ?? 0,
      };
    } catch (_) {
      return {
        'current_streak': 0,
        'longest_streak': 0,
        'total_days': 0,
      };
    }
  }
}
