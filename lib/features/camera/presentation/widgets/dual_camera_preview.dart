import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DualCameraPreview extends StatelessWidget {
  const DualCameraPreview({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return const UiKitView(
        viewType: 'two_camera/preview',
        creationParamsCodec: StandardMessageCodec(),
      );
    } else {
      return const Center(
        child: Text(
          'Camera preview not supported on this platform.',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
  }
}
