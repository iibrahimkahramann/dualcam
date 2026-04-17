import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

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
      return Center(
        child: Text(
          'camera_not_supported'.tr(),
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
  }
}
