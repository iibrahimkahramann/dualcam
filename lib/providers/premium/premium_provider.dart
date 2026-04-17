import 'package:flutter_riverpod/legacy.dart';

class PremiumNotifier extends StateNotifier<bool> {
  // SET TO TRUE FOR TESTING PREMIUM STATE
  PremiumNotifier() : super(false) {
    _initializePremiumStatus();
  }

  Future<void> _initializePremiumStatus() async {
    // örnek: SharedPreferences ya da RevenueCat kontrolü vs.
    // final bool fromStorage = await loadPremiumStatus();
    // state = fromStorage;
  }

  Future<void> updatePremiumStatus(bool isPremium) async {
    state = isPremium;
  }
}

final isPremiumProvider = StateNotifierProvider<PremiumNotifier, bool>((ref) {
  return PremiumNotifier();
});
