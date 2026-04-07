import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class StripeService {
  // Publishable key — replace with your actual key
  static const String publishableKey = 'YOUR_STRIPE_PUBLISHABLE_KEY';

  // Your backend URL — using Supabase Edge Function
  static const String backendUrl = 'YOUR_SUPABASE_EDGE_FUNCTION_URL';

  static Future<void> initialize() async {
    try {
      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();
    } catch (e) {
      debugPrint('Stripe init error: $e');
    }
  }

  // Free tier limits
  static const int freeBookLimit = 5;

  // Plans
  static const String monthlyPriceId = 'YOUR_MONTHLY_PRICE_ID';
  static const String yearlyPriceId = 'YOUR_YEARLY_PRICE_ID';

  static Future<bool> startSubscription({
    required String priceId,
    required String userEmail,
  }) async {
    try {
      // This will call your Supabase Edge Function
      // to create a payment intent
      // For now return false — will implement
      // when Edge Function is ready
      return false;
    } catch (e) {
      debugPrint('Stripe error: $e');
      return false;
    }
  }
}
