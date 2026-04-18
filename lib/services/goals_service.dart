import 'package:shared_preferences/shared_preferences.dart';

class ReadingGoal {
  final int dailyMinutes;
  final int weeklyBooks;
  final int yearlyBooks;

  const ReadingGoal({
    this.dailyMinutes = 30,
    this.weeklyBooks = 1,
    this.yearlyBooks = 12,
  });
}

class GoalsService {
  static Future<void> saveGoal(ReadingGoal goal) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('goal_daily_minutes', goal.dailyMinutes);
      await prefs.setInt('goal_weekly_books', goal.weeklyBooks);
      await prefs.setInt('goal_yearly_books', goal.yearlyBooks);
    } catch (_) {}
  }

  static Future<ReadingGoal> loadGoal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ReadingGoal(
        dailyMinutes: prefs.getInt('goal_daily_minutes') ?? 30,
        weeklyBooks: prefs.getInt('goal_weekly_books') ?? 1,
        yearlyBooks: prefs.getInt('goal_yearly_books') ?? 12,
      );
    } catch (_) {
      return const ReadingGoal();
    }
  }

  static Future<double> getDailyProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final goal = await loadGoal();
      final todayKey =
          DateTime.now().toIso8601String().split('T')[0];
      final todayMinutes =
          prefs.getInt('today_minutes_$todayKey') ?? 0;
      return (todayMinutes / goal.dailyMinutes).clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  static Future<void> recordMinutes(int minutes) async {
    if (minutes <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey =
          DateTime.now().toIso8601String().split('T')[0];
      final existing =
          prefs.getInt('today_minutes_$todayKey') ?? 0;
      await prefs.setInt(
          'today_minutes_$todayKey', existing + minutes);
    } catch (_) {}
  }
}
