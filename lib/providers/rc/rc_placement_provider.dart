import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

Future<void> showPaywallWithPlacement(
  String placementId,
  String entitlementId,
) async {
  try {
    // Placement üzerinden offering almaya çalış
    final offering = await Purchases.getCurrentOfferingForPlacement(
      placementId,
    );

    if (offering != null) {
      // Placement üzerinden gelen offering ile paywall göster
      final result = await RevenueCatUI.presentPaywallIfNeeded(
        entitlementId,
        offering: offering,
      );
      print("✅ Paywall result for placement '$placementId': $result");
    } else {
      // Placement bulunamadıysa → doğrudan entitlement üzerinden default paywall göster
      print(
        "⚠️ Placement '$placementId' için offering yok. Default entitlement paywall gösteriliyor...",
      );

      final fallbackResult = await RevenueCatUI.presentPaywallIfNeeded(
        entitlementId,
      );
      print("✅ Default paywall result: $fallbackResult");
    }
  } catch (e, stack) {
    print("🚨 Hata oluştu: $e\n$stack");
  }
}

/// 1️⃣ Offerings (offeringId bazlı)
// final offeringProvider = FutureProvider.family<Offering?, String>((
  // ref,
  // offeringId,
// ) async {
  // // opsiyonel: en güncel veriyi almak istersen cache'i temizle
  // // await Purchases.invalidateOfferingsCache();
  // final offerings = await Purchases.getOfferings();
  // return offerings.all[offeringId];
// });

// /// 2️⃣ CustomerInfo StateNotifier (abonelik durumu)
// class CustomerInfoNotifier extends StateNotifier<CustomerInfo?> {
  // CustomerInfoNotifier(CustomerInfo? initialInfo) : super(initialInfo) {
    // // Listen for future updates from the SDK
    // Purchases.addCustomerInfoUpdateListener((customerInfo) {
      // state = customerInfo;
    // });
  // }

  // Future<void> refresh() async {
    // await Purchases.invalidateCustomerInfoCache();
    // final info = await Purchases.getCustomerInfo();
    // state = info;
  // }

  // // 🔹 Güvenli dış erişim için özel fonksiyon
  // void update(CustomerInfo? info) {
    // state = info;
  // }
// }

// final customerInfoProvider =
    // StateNotifierProvider<CustomerInfoNotifier, CustomerInfo?>((ref) {
      // return CustomerInfoNotifier(null);
    // });

// ///  Satın alma & restore işlemleri

// final purchaseActionProvider = Provider((ref) {
  // Future<PurchaseResult> purchasePackage(Package package) async {
    // try {
      // final result = await Purchases.purchasePackage(package);

      // // 🔹 artık böyle güncelle
      // ref.read(customerInfoProvider.notifier).update(result.customerInfo);

      // return result;
    // } catch (e) {
      // rethrow;
    // }
  // }

  // Future<CustomerInfo> restorePurchases() async {
    // final customerInfo = await Purchases.restorePurchases();
    // ref.read(customerInfoProvider.notifier).update(customerInfo);
    // return customerInfo;
  // }

  // return {
    // 'purchasePackage': purchasePackage,
    // 'restorePurchases': restorePurchases,
  // };
// });
