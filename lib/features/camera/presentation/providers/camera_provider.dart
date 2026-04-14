import 'dart:async';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/repositories/camera_repository.dart';
import '../../data/repositories/camera_repository_impl.dart';
import '../../data/datasources/camera_native_datasource.dart';
import 'camera_state.dart';

// Provides the repository
final cameraRepositoryProvider = Provider<CameraRepository>((ref) {
  final dataSource = CameraNativeDataSource();
  return CameraRepositoryImpl(dataSource);
});

// UI State Providers
class SuccessBannerNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? text) => state = text;
}
final successBannerProvider = NotifierProvider<SuccessBannerNotifier, String?>(SuccessBannerNotifier.new);

class RecordButtonPressedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool pressed) => state = pressed;
}
final recordButtonPressedProvider = NotifierProvider<RecordButtonPressedNotifier, bool>(RecordButtonPressedNotifier.new);

class ShowExposureSliderNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void hide() => state = false;
}
final showExposureSliderProvider = NotifierProvider<ShowExposureSliderNotifier, bool>(ShowExposureSliderNotifier.new);

class TimerDurationNotifier extends Notifier<int> {
  @override
  int build() => 0; // 0 (off), 3, 5, 10
  void set(int duration) => state = duration;
}
final timerDurationProvider = NotifierProvider<TimerDurationNotifier, int>(TimerDurationNotifier.new);

class ActiveTimerCountdownNotifier extends Notifier<int?> {
  @override
  int? build() => null; // null means not counting
  void set(int? seconds) => state = seconds;
}
final activeTimerCountdownProvider = NotifierProvider<ActiveTimerCountdownNotifier, int?>(ActiveTimerCountdownNotifier.new);

class HdrEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  Future<void> toggle() async {
    final newState = !state;
    state = newState;
    await ref.read(cameraRepositoryProvider).setHDR(newState);
  }
}
final hdrEnabledProvider = NotifierProvider<HdrEnabledNotifier, bool>(HdrEnabledNotifier.new);

class GridEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}
final gridEnabledProvider = NotifierProvider<GridEnabledNotifier, bool>(GridEnabledNotifier.new);

class ExposureValueNotifier extends Notifier<double> {
  @override
  double build() => 0.0;
  Future<void> set(double bias) async {
    state = bias;
    await ref.read(cameraRepositoryProvider).setExposure(bias);
  }
}
final exposureValueProvider = NotifierProvider<ExposureValueNotifier, double>(ExposureValueNotifier.new);

class FocusPointNotifier extends Notifier<Offset?> {
  @override
  Offset? build() => null;
  Future<void> focusAt(Offset point) async {
    state = point;
    // x and y must be between 0.0 and 1.0 (relative to preview size)
    await ref.read(cameraRepositoryProvider).setFocusPoint(point.dx, point.dy);
  }
  void clear() => state = null;
}
final focusPointProvider = NotifierProvider<FocusPointNotifier, Offset?>(FocusPointNotifier.new);

final resolutionsListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await ref.read(cameraRepositoryProvider).getAvailableResolutions();
});

class ActiveResolutionNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;
  Future<void> set(Map<String, dynamic> res) async {
    state = res;
    await ref.read(cameraRepositoryProvider).setResolution(res['width']!, res['height']!, res['fps'] ?? 30);
  }
}
final activeResolutionProvider = NotifierProvider<ActiveResolutionNotifier, Map<String, dynamic>?>(ActiveResolutionNotifier.new);

final maxZoomProvider = FutureProvider<double>((ref) async {
  return await ref.read(cameraRepositoryProvider).getMaxZoom();
});

class ZoomLevelNotifier extends Notifier<double> {
  @override
  double build() => 1.0;
  
  Future<void> set(double factor) async {
    // We optionally clamp to max bounds dynamically in the view before passing here, 
    // but the native layer also clamps it for safety.
    state = factor;
    await ref.read(cameraRepositoryProvider).setZoom(factor);
  }
}
final zoomLevelProvider = NotifierProvider<ZoomLevelNotifier, double>(ZoomLevelNotifier.new);

class BaseZoomNotifier extends Notifier<double> {
  @override
  double build() => 1.0;
  void set(double val) => state = val;
}
final baseZoomProvider = NotifierProvider<BaseZoomNotifier, double>(BaseZoomNotifier.new);

class RecordingDurationNotifier extends Notifier<int> {
  Timer? _timer;

  @override
  int build() => 0;

  void start() {
    state = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      state++;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    state = 0;
  }
}
final recordingDurationProvider = NotifierProvider<RecordingDurationNotifier, int>(RecordingDurationNotifier.new);

class IsPipSwappedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  void toggle() {
    state = !state;
    print("PIP SWAPPED STATE: $state");
  }
}
final isPipSwappedProvider = NotifierProvider<IsPipSwappedNotifier, bool>(IsPipSwappedNotifier.new);

class IsFrontCameraNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  Future<void> toggle() async {
    // Reset flash safely if switching cameras
    final flashNotifier = ref.read(isFlashEnabledProvider.notifier);
    if (ref.read(isFlashEnabledProvider)) {
        await flashNotifier.forceOff(); // custom method we'll add
    }

    final newState = !state;
    state = newState;
    await ref.read(cameraRepositoryProvider).switchCamera();
    // Reset configuration limits for the new camera
    ref.invalidate(resolutionsListProvider);
    ref.invalidate(maxZoomProvider);
    // Reset control values visually inside Dart bounds
    ref.read(zoomLevelProvider.notifier).set(1.0);
    ref.read(baseZoomProvider.notifier).set(1.0);
    ref.read(exposureValueProvider.notifier).set(0.0);
  }
}
final isFrontCameraProvider = NotifierProvider<IsFrontCameraNotifier, bool>(IsFrontCameraNotifier.new);

class IsFlashEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  double _previousBrightness = 0.5;
  
  Future<void> toggle() async {
    final newState = !state;
    state = newState;
    
    final repo = ref.read(cameraRepositoryProvider);
    final isFrontCamera = ref.read(isFrontCameraProvider);
    
    if (newState && isFrontCamera) {
       _previousBrightness = await repo.getScreenBrightness();
       await repo.setScreenBrightness(1.0); // Full brightness for front camera flash
    } else if (!newState && isFrontCamera) {
       await repo.setScreenBrightness(_previousBrightness);
    }
    
    // Always attempt native torch (it ignores safely if hardware doesn't exist)
    await repo.toggleTorch(newState);
  }

  Future<void> forceOff() async {
    if (!state) return;
    state = false;
    final repo = ref.read(cameraRepositoryProvider);
    if (ref.read(isFrontCameraProvider)) {
        await repo.setScreenBrightness(_previousBrightness);
    }
    await repo.toggleTorch(false);
  }
}
final isFlashEnabledProvider = NotifierProvider<IsFlashEnabledNotifier, bool>(IsFlashEnabledNotifier.new);

// The principal Notifier holding the camera state
final cameraProvider = AsyncNotifierProvider<CameraNotifier, CameraState>(() {
  return CameraNotifier();
});

class CameraNotifier extends AsyncNotifier<CameraState> {
  late final CameraRepository _repository;

  @override
  FutureOr<CameraState> build() {
    _repository = ref.read(cameraRepositoryProvider);
    return const CameraState();
  }

  Future<void> initialize() async {
    state = const AsyncValue.loading();
    try {
      await _repository.initialize();
      state = AsyncValue.data(const CameraState(isInitialized: true));
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      state = AsyncValue.data(CameraState(errorMessage: e.toString()));
    }
  }

  Future<void> startRecording() async {
    final current = state.value;
    if (current == null || !current.isInitialized) return;

    try {
      await _repository.startRecording();
      state = AsyncValue.data(current.copyWith(isRecording: true));
      ref.read(recordingDurationProvider.notifier).start();
    } catch (e) {
      state = AsyncValue.data(current.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> stopRecording() async {
    final current = state.value;
    if (current == null || !current.isRecording) return;

    try {
      final files = await _repository.stopRecording();
      state = AsyncValue.data(current.copyWith(
        isRecording: false,
        recordedFiles: files,
      ));
      ref.read(recordingDurationProvider.notifier).stop();
    } catch (e) {
      state = AsyncValue.data(current.copyWith(
        isRecording: false,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> takePhoto() async {
    final current = state.value;
    if (current == null || !current.isInitialized || current.isRecording) return;

    try {
      final files = await _repository.takePhoto();
      state = AsyncValue.data(current.copyWith(
        recordedFiles: files,
      ));
    } catch (e) {
      state = AsyncValue.data(current.copyWith(
        errorMessage: e.toString(),
      ));
    }
  }

  void setMode(bool isPhoto) {
    final current = state.value;
    if (current != null && !current.isRecording) {
      state = AsyncValue.data(current.copyWith(isPhotoMode: isPhoto));
    }
  }

  void clearError() {
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.clearError());
    }
  }
}
