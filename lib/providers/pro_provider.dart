import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProNotifier extends StateNotifier<bool> {
  ProNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool('is_pro') ?? false;
    } catch (_) {}
  }

  Future<void> setPro(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_pro', value);
      state = value;
    } catch (_) {}
  }
}

final StateNotifierProvider<ProNotifier, bool> isProProvider =
    StateNotifierProvider<ProNotifier, bool>((Ref ref) => ProNotifier());
