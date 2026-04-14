import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui' show ImageFilter;
import '../providers/camera_provider.dart';
import '../widgets/dual_camera_preview.dart';
import '../widgets/camera_horizontal_preview.dart';
import '../widgets/record_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';

final GlobalKey dualCameraKey = GlobalKey(debugLabel: 'dual');
final GlobalKey horizCameraKey = GlobalKey(debugLabel: 'horiz');

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CameraView extends ConsumerStatefulWidget {
  const CameraView({super.key});

  @override
  ConsumerState<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends ConsumerState<CameraView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cameraProvider.notifier).initialize();
    });
  }

  void _triggerSuccessBanner(String text) async {
    ref.read(successBannerProvider.notifier).set(text);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      ref.read(successBannerProvider.notifier).set(null);
    }
  }

  void _handleCaptureAction(bool isPhotoMode, bool isRecording) async {
    final timerDuration = ref.read(timerDurationProvider);
    if (timerDuration > 0 && (!isRecording || isPhotoMode)) {
      for (int i = timerDuration; i > 0; i--) {
        if (!mounted) return;
        ref.read(activeTimerCountdownProvider.notifier).set(i);
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      ref.read(activeTimerCountdownProvider.notifier).set(null);
    }

    if (isPhotoMode) {
      ref.read(cameraProvider.notifier).takePhoto();
    } else {
      if (isRecording) {
        ref.read(cameraProvider.notifier).stopRecording();
      } else {
        ref.read(cameraProvider.notifier).startRecording();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cameraProvider, (previous, next) {
      final prevFiles = previous?.value?.recordedFiles;
      final nextFiles = next.value?.recordedFiles;
      if (nextFiles != null && nextFiles != prevFiles && nextFiles.isNotEmpty) {
        final isPhoto = next.value?.isPhotoMode ?? false;
        _triggerSuccessBanner(
          isPhoto
              ? "Fotoğraf galeriye kaydedildi."
              : "Video galeriye kaydedildi.",
        );
      }
    });

    final cameraStateAsync = ref.watch(cameraProvider);
    final state = cameraStateAsync.value;
    final isRecording = state?.isRecording ?? false;
    final isPhotoMode = state?.isPhotoMode ?? false;

    final successBannerText = ref.watch(successBannerProvider);
    final isBannerVisible = successBannerText != null;

    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    final pipBaseSize = size.width * (isTablet ? 0.4 : 0.48);
    final _ = isTablet ? size.height * 0.12 : size.height * 0.16;

    final isPipSwapped = ref.watch(isPipSwappedProvider);

    final activeTimer = ref.watch(activeTimerCountdownProvider);
    final focusPoint = ref.watch(focusPointProvider);
    final gridEnabled = ref.watch(gridEnabledProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Vertical Native Preview (Background) with Tap-to-Focus & Exposure Drag
          Positioned.fill(
            child: GestureDetector(
              onTapDown: (details) {
                // Hide EV slider if tapped anywhere else
                if (ref.read(showExposureSliderProvider)) {
                  ref.read(showExposureSliderProvider.notifier).hide();
                }

                final ratioX = details.localPosition.dx / size.width;
                final ratioY = details.localPosition.dy / size.height;
                ref
                    .read(focusPointProvider.notifier)
                    .focusAt(Offset(ratioX, ratioY));

                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted && ref.read(focusPointProvider) != null) {
                    ref.read(focusPointProvider.notifier).clear();
                  }
                });
              },
              onScaleStart: (details) {
                // Mark the current zoom as base for the pinch-to-zoom calculation
                ref
                    .read(baseZoomProvider.notifier)
                    .set(ref.read(zoomLevelProvider));
              },
              onScaleUpdate: (details) {
                final maxZoom = ref.read(maxZoomProvider).value ?? 5.0;
                final base = ref.read(baseZoomProvider);
                final newZoom = (base * details.scale).clamp(1.0, maxZoom);
                ref.read(zoomLevelProvider.notifier).set(newZoom);
              },
              child: Container(
                color: Colors.black,
                child: isPipSwapped
                    ? Center(
                        child: AspectRatio(
                          aspectRatio:
                              16.0 /
                              9.0, // Horizontal 16:9 stream fit onto the screen
                          child: CameraHorizontalPreview(key: horizCameraKey),
                        ),
                      )
                    : DualCameraPreview(key: dualCameraKey),
              ),
            ),
          ),

          // Grid Overlay
          if (gridEnabled)
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: GridPainter())),
            ),

          // Focus Square
          if (focusPoint != null)
            Positioned(
              left: focusPoint.dx * size.width - 35,
              top: focusPoint.dy * size.height - 35,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: 1.0,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.yellowAccent, width: 2),
                  ),
                ),
              ),
            ),
          // Screen Flash (Apple-style white border for front camera)
          if (ref.watch(isFrontCameraProvider) && ref.watch(isFlashEnabledProvider))
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFFFF9E6), // Warm white illumination
                      width: 50.0, // Thick border mimicking Apple's Retina Flash
                    ),
                  ),
                ),
              ),
            ),

          // 2. UI overlays
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Glassmorphism Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 9:16 indicator or Recording Indicator
                            isRecording
                                ? Row(
                                    children: [
                                      const Icon(
                                        CupertinoIcons.circle_fill,
                                        color: Colors.red,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 6),
                                      Consumer(
                                        builder: (context, ref, _) {
                                          final seconds = ref.watch(
                                            recordingDurationProvider,
                                          );
                                          final m = (seconds / 60)
                                              .floor()
                                              .toString()
                                              .padLeft(2, '0');
                                          final s = (seconds % 60)
                                              .toString()
                                              .padLeft(2, '0');
                                          return Text(
                                            "$m:$s",
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.w600,
                                              fontSize: isTablet ? 18 : 14,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  )
                                : Text(
                                    isPipSwapped
                                        ? '16:9 (Yatay)'
                                        : '9:16 (Dikey)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isTablet ? 18 : 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                            // Settings Items & Resolution
                            if (!isRecording)
                              Row(
                                children: [
                                  // Flash/Torch Toggle
                                  GestureDetector(
                                    onTap: () => ref
                                        .read(isFlashEnabledProvider.notifier)
                                        .toggle(),
                                    child: Icon(
                                      ref.watch(isFlashEnabledProvider)
                                          ? CupertinoIcons.bolt_fill
                                          : CupertinoIcons.bolt_slash,
                                      color: ref.watch(isFlashEnabledProvider)
                                          ? Colors.yellow
                                          : Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Exposure (EV) Toggle
                                  GestureDetector(
                                    onTap: () => ref
                                        .read(
                                          showExposureSliderProvider.notifier,
                                        )
                                        .toggle(),
                                    child: Icon(
                                      ref.watch(showExposureSliderProvider)
                                          ? CupertinoIcons.slider_horizontal_3
                                          : CupertinoIcons.slider_horizontal_3,
                                      color:
                                          ref.watch(showExposureSliderProvider)
                                          ? Colors.yellow
                                          : Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // HDR Toggle
                                  GestureDetector(
                                    onTap: () => ref
                                        .read(hdrEnabledProvider.notifier)
                                        .toggle(),
                                    child: Icon(
                                      ref.watch(hdrEnabledProvider)
                                          ? CupertinoIcons.sun_max_fill
                                          : CupertinoIcons.sun_max,
                                      color: ref.watch(hdrEnabledProvider)
                                          ? Colors.yellow
                                          : Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Grid Toggle
                                  GestureDetector(
                                    onTap: () => ref
                                        .read(gridEnabledProvider.notifier)
                                        .toggle(),
                                    child: Icon(
                                      ref.watch(gridEnabledProvider)
                                          ? CupertinoIcons.grid
                                          : CupertinoIcons.grid,
                                      color: ref.watch(gridEnabledProvider)
                                          ? Colors.yellow
                                          : Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 18),

                                  // Timer Toggle
                                  GestureDetector(
                                    onTap: () {
                                      final current = ref.read(
                                        timerDurationProvider,
                                      );
                                      final next = current == 0
                                          ? 3
                                          : (current == 3
                                                ? 5
                                                : (current == 5 ? 10 : 0));
                                      ref
                                          .read(timerDurationProvider.notifier)
                                          .set(next);
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          ref.watch(timerDurationProvider) > 0
                                              ? CupertinoIcons.timer_fill
                                              : CupertinoIcons.timer,
                                          color:
                                              ref.watch(timerDurationProvider) >
                                                  0
                                              ? Colors.yellow
                                              : Colors.white,
                                          size: 22,
                                        ),
                                        if (ref.watch(timerDurationProvider) >
                                            0) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            "${ref.watch(timerDurationProvider)}s",
                                            style: const TextStyle(
                                              color: Colors.yellow,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Active Resolution (4K • 60) Action Sheet
                                  Consumer(
                                    builder: (context, ref, child) {
                                      final resolutionsAsync = ref.watch(
                                        resolutionsListProvider,
                                      );
                                      final activeRes = ref.watch(
                                        activeResolutionProvider,
                                      );
                                      return resolutionsAsync.when(
                                        data: (resolutions) {
                                          if (resolutions.isEmpty)
                                            return const SizedBox();
                                          final displayRes =
                                              activeRes ?? resolutions.first;
                                          final label =
                                              displayRes['label'] ??
                                              "${displayRes['width']}x${displayRes['height']}";

                                          return GestureDetector(
                                            onTap: () {
                                              showCupertinoModalPopup(
                                                context: context,
                                                builder: (context) => CupertinoActionSheet(
                                                  title: const Text(
                                                    "video_format",
                                                  ).tr(),
                                                  message: const Text(
                                                    "select_resolution_fps",
                                                  ).tr(),
                                                  actions: resolutions.map((
                                                    res,
                                                  ) {
                                                    final resLabel =
                                                        res['label'] ??
                                                        "${res['width']}x${res['height']} • ${res['fps'] ?? 30}";
                                                    return CupertinoActionSheetAction(
                                                      onPressed: () {
                                                        ref
                                                            .read(
                                                              activeResolutionProvider
                                                                  .notifier,
                                                            )
                                                            .set(res);
                                                        Navigator.pop(context);
                                                      },
                                                      child: Text(
                                                        resLabel,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                  cancelButton:
                                                      CupertinoActionSheetAction(
                                                        isDestructiveAction:
                                                            true,
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                            ),
                                                        child: const Text(
                                                          "cancel",
                                                        ).tr(),
                                                      ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                  0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isTablet ? 16 : 14,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        loading: () => const SizedBox(),
                                        error: (e, st) => const SizedBox(),
                                      );
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Error Message if any
                if (state?.errorMessage != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      state!.errorMessage!,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Spacer to push the bottom elements down
                const Spacer(),

                // Custom Zoom Controls (1x, 2x, 5x)
                if (!isRecording)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final maxZoomAsync = ref.watch(maxZoomProvider);
                        final maxZoom = maxZoomAsync.value ?? 1.0;
                        final currentZoom = ref.watch(zoomLevelProvider);

                        if (maxZoom <= 1.1) return const SizedBox();

                        List<double> zoomLevels = [1.0];
                        if (maxZoom >= 2.0) zoomLevels.add(2.0);
                        if (maxZoom >= 5.0) zoomLevels.add(5.0);

                        return Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: zoomLevels.map((lvl) {
                                    final isActive =
                                        (currentZoom - lvl).abs() <
                                        0.3; // Threshold for active highlight
                                    return GestureDetector(
                                      onTap: () => ref
                                          .read(zoomLevelProvider.notifier)
                                          .set(lvl),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        width: 38,
                                        height: 38,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isActive
                                              ? Colors.yellow
                                              : Colors.transparent,
                                          border: isActive
                                              ? null
                                              : Border.all(
                                                  color: Colors.white30,
                                                ),
                                        ),
                                        child: Text(
                                          lvl == lvl.toInt()
                                              ? "${lvl.toInt()}x"
                                              : "${lvl}x",
                                          style: TextStyle(
                                            color: isActive
                                                ? Colors.black
                                                : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // Mode Selectors
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: isRecording
                          ? null
                          : () => ref
                                .read(cameraProvider.notifier)
                                .setMode(false), // Video Mode
                      child: Text(
                        "VIDEO",
                        style: TextStyle(
                          color: !isPhotoMode ? Colors.yellow : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: isTablet ? 20 : 16,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    SizedBox(width: isTablet ? 50 : 30),
                    GestureDetector(
                      onTap: isRecording
                          ? null
                          : () => ref
                                .read(cameraProvider.notifier)
                                .setMode(true), // Photo Mode
                      child: Text(
                        "PHOTO",
                        style: TextStyle(
                          color: isPhotoMode ? Colors.yellow : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: isTablet ? 20 : 16,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: size.height * 0.02),

                // Bottom Bar: Record Button and Camera Switch
                Padding(
                  padding: EdgeInsets.only(bottom: size.height * 0.04),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Invisible spacer for flex balance
                      const Expanded(child: SizedBox()),
                      
                      // Centered record button
                      RecordButton(
                        isRecording: isRecording,
                        isPhotoMode: isPhotoMode,
                        onTap: () => _handleCaptureAction(isPhotoMode, isRecording),
                      ),
                      
                      // Camera switch to the right
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 30),
                            child: isRecording
                                ? const SizedBox()
                                : GestureDetector(
                                    onTap: () => ref.read(isFrontCameraProvider.notifier).toggle(),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.4),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.camera_rotate,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Loading state overlay
          if (cameraStateAsync.isLoading)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // Custom Animated Success Banner
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            top: isBannerVisible
                ? MediaQuery.of(context).padding.top + 20
                : -100,
            left: 20,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        successBannerText ?? "",
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Vertical Exposure Slider Overlay
          if (ref.watch(showExposureSliderProvider))
            Positioned(
              right: 20,
              top: size.height * 0.3,
              bottom: size.height * 0.3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: RotatedBox(
                      quarterTurns: 3, // Makes the horizontal slider vertical
                      child: CupertinoSlider(
                        value: ref.watch(exposureValueProvider),
                        min: -8.0,
                        max: 8.0,
                        activeColor: Colors.yellow,
                        onChanged: (val) {
                          ref.read(exposureValueProvider.notifier).set(val);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Big Timer Overlay
          if (activeTimer != null)
            Positioned.fill(
              child: Center(
                child: Text(
                  "$activeTimer",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 120,
                    fontWeight: FontWeight.bold,
                    shadows: const [
                      Shadow(color: Colors.black45, blurRadius: 15),
                    ],
                  ),
                ),
              ),
            ),

          // Floating PIP View (Animated)
          Consumer(
            builder: (context, ref, child) {
              final isPipSwapped = ref.watch(isPipSwappedProvider);
              final pipWidth = isPipSwapped ? (pipBaseSize * 0.5) : pipBaseSize;
              final pipHeight = isPipSwapped
                  ? ((pipBaseSize * 0.5) * (16.0 / 9.0))
                  : (pipBaseSize * (9.0 / 16.0));

              // Top padding to sit under black bar offset when swapped, or slightly above Zoom Buttons when Normal
              final pipTop = isPipSwapped
                  ? (MediaQuery.of(context).padding.top +
                        (isTablet ? 120.0 : 80.0))
                  : (size.height - pipHeight - (isTablet ? 300.0 : 270.0));

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                top: pipTop,
                left: (size.width - pipWidth) / 2, // Centered horizontally
                width: pipWidth,
                height: pipHeight,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.yellow,
                      width: isTablet ? 3 : 2,
                    ),
                    borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                    color: Colors.black,
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 10),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isTablet ? 9 : 6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        isPipSwapped
                            ? DualCameraPreview(key: dualCameraKey)
                            : CameraHorizontalPreview(key: horizCameraKey),

                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            ref.read(isPipSwappedProvider.notifier).toggle();
                          },
                          child: Container(color: Colors.transparent),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
