import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static bool get isInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser {
    if (!isInitialized) return null;
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  static bool get isLoggedIn => currentUser != null;
  static String? get userId => currentUser?.id;
  static String? get userEmail => currentUser?.email;

  static Stream<AuthState> get authStateChanges {
    try {
      return client.auth.onAuthStateChange;
    } catch (_) {
      return const Stream.empty();
    }
  }

  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
  }

  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (_) {}
  }

  static Future<UserResponse> updateUserName(String name) async {
    return await client.auth.updateUser(
      UserAttributes(data: {'full_name': name}),
    );
  }
}
