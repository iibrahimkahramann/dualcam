import 'dart:io';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

Future<void> appTracking() async {
  if (!Platform.isIOS) return;
  final status = await AppTrackingTransparency.trackingAuthorizationStatus;
  if (status == TrackingStatus.notDetermined) {
    await Future.delayed(const Duration(milliseconds: 300));
    await AppTrackingTransparency.requestTrackingAuthorization();
  }
}

Future<void> nottrack() async {}
