import 'package:go_router/go_router.dart';
import '../../features/splash/splash_view.dart';
import '../../features/camera/presentation/views/camera_view.dart';
import '../../features/settings/presentation/views/settings_view.dart';
import '../../features/onboarding/presentation/views/onboarding_view.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashView(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingView(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const CameraView(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsView(),
    ),
  ],
);
