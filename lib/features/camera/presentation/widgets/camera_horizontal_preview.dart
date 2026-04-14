import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraHorizontalPreview extends StatelessWidget {
  const CameraHorizontalPreview({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return Container(
        color: Colors.black,
        child: const UiKitView(
          viewType: 'two_camera/horizontal_preview',
          creationParamsCodec: StandardMessageCodec(),
        ),
      );
    } else {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.error, color: Colors.white),
        ),
      );
    }
  }
}
