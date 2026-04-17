import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:two_camera/core/routing/app_router.dart';
import 'package:two_camera/firebase_options.dart';
import 'package:two_camera/providers/premium/premium_provider.dart';
import 'package:two_camera/utils/app_tracking.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ❌ RevenueCat'i burada await ile çağırma — iOS gesture engine'ini bloke eder!
  // ✅ Splash ekranı gösterilirken arka planda başlatılacak (MyAppState.initState)

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en', ''),
        Locale('tr', ''),
        Locale('fr', ''),
        Locale('it', ''),
        Locale('pt', ''),
        Locale('es', ''),
        Locale('de', ''),
        Locale('ru', ''),
        Locale('ko', ''),
        Locale('ja', ''),
        Locale('id', ''),
        Locale('hi', ''),
        Locale('ar', ''),
      ],
      path: 'assets/langs',
      fallbackLocale: const Locale('en', ''),
      useOnlyLangCode: true,
      child: ProviderScope(child: const MyApp()),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});
  @override
  ConsumerState<MyApp> createState() => MyAppState();
}

class MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Her şeyi post-frame'de başlat — initState'te native SDK çağırmak gesture'ları bloke eder
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _configureRcsdk();
      if (Platform.isIOS) {
        Future.delayed(const Duration(seconds: 3), () => appTracking());
      }
    });
  }

  Future<void> _configureRcsdk() async {
    try {
      print("Configure Rcsdk *************");
      await Purchases.setLogLevel(LogLevel.debug);
      PurchasesConfiguration? configuration;

      if (Platform.isAndroid) {
        configuration = PurchasesConfiguration(
          "appl_JPDSIFvEMRVEHGdpZfHqWKZBAdx",
        );
      } else if (Platform.isIOS) {
        configuration = PurchasesConfiguration(
          "appl_JPDSIFvEMRVEHGdpZfHqWKZBAdx",
        );
      }
      if (configuration != null) {
        await Purchases.configure(configuration);
      }
      _setupRevenueCatListener();
    } catch (e) {
      debugPrint("RevenueCat init error: $e");
    }
  }

  void _setupRevenueCatListener() {
    Purchases.addCustomerInfoUpdateListener((customerInfo) async {
      if (!mounted) return;
      final entitlement = customerInfo.entitlements.all["premium"];
      ref
          .read(isPremiumProvider.notifier)
          .updatePremiumStatus(entitlement?.isActive ?? false);
      print("Riverpod ile abone kontrolü: ${entitlement?.isActive ?? false}");
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DualCam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}
