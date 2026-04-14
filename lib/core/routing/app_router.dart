import 'package:go_router/go_router.dart';
import '../../features/camera/presentation/views/camera_view.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const CameraView(),
    ),
  ],
);
