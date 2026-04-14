import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/camera_provider.dart';

class RecordButton extends ConsumerWidget {
  final bool isRecording;
  final bool isPhotoMode;
  final VoidCallback onTap;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.isPhotoMode,
    required this.onTap,
  });

  void _handleTapDown(WidgetRef ref) {
    if (isPhotoMode) {
      ref.read(recordButtonPressedProvider.notifier).set(true);
    }
  }

  void _handleTapUp(WidgetRef ref) {
    if (isPhotoMode) {
      ref.read(recordButtonPressedProvider.notifier).set(false);
    }
  }

  void _handleTapCancel(WidgetRef ref) {
    if (isPhotoMode) {
      ref.read(recordButtonPressedProvider.notifier).set(false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPressed = ref.watch(recordButtonPressedProvider);
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;
    
    // Scale button size based on screen width
    final buttonOuterSize = (size.width * 0.18).clamp(70.0, 110.0);
    final buttonInnerBase = buttonOuterSize * 0.75; // e.g. 60 vs 80
    final buttonInnerPressed = buttonOuterSize * 0.62; // e.g. 50 vs 80
    final buttonInnerRecording = buttonOuterSize * 0.37; // e.g. 30 vs 80

    return GestureDetector(
      onTapDown: (_) => _handleTapDown(ref),
      onTapUp: (_) => _handleTapUp(ref),
      onTapCancel: () => _handleTapCancel(ref),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: buttonOuterSize,
        height: buttonOuterSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: isTablet ? 6 : 4,
          ),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: isRecording ? buttonInnerRecording : (isPhotoMode && isPressed ? buttonInnerPressed : buttonInnerBase),
            height: isRecording ? buttonInnerRecording : (isPhotoMode && isPressed ? buttonInnerPressed : buttonInnerBase),
            decoration: BoxDecoration(
              color: isPhotoMode ? (isPressed ? Colors.grey[400] : Colors.white) : Colors.red,
              shape: BoxShape.rectangle,
              borderRadius: isRecording 
                  ? BorderRadius.circular(isTablet ? 12 : 8) 
                  : BorderRadius.circular(buttonOuterSize / 2),
            ),
          ),
        ),
      ),
    );
  }
}
