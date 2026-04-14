import 'package:flutter/services.dart';

class CameraNativeDataSource {
  static const MethodChannel _channel = MethodChannel('com.two_camera/channel');

  Future<void> initialize() async {
    try {
      final result = await _channel.invokeMethod<bool>('initialize');
      if (result != true) {
        throw Exception('Failed to initialize camera');
      }
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Unknown Platform Exception');
    }
  }

  Future<void> startRecording() async {
    try {
      final result = await _channel.invokeMethod<bool>('startRecording');
      if (result != true) {
        throw Exception('Failed to start recording');
      }
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Unknown Platform Exception');
    }
  }

  Future<List<String>> stopRecording() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('stopRecording');
      if (result == null || result.length < 2) {
        throw Exception('Failed to stop recording or invalid result format');
      }
      return result.map((e) => e.toString()).toList();
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Unknown Platform Exception');
    }
  }

  Future<List<String>> takePhoto() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('takePhoto');
      if (result == null || result.length < 2) {
        throw Exception('Failed to take photo or invalid result format');
      }
      return result.map((e) => e.toString()).toList();
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Unknown Platform Exception');
    }
  }

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<bool>('dispose');
    } catch (_) {
      // Ignore dispose errors
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableResolutions() async {
    try {
      final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getAvailableResolutions');
      if (result == null) return [];
      return result.map((e) => {
        'width': e['width'] as int,
        'height': e['height'] as int,
        'fps': e['fps'] as int,
        'label': e['label'] as String
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<double> getMaxZoom() async {
    try {
      final result = await _channel.invokeMethod<double>('getMaxZoom');
      return result ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  Future<void> setZoom(double factor) async {
    await _channel.invokeMethod('setZoom', factor);
  }

  Future<void> setResolution(int width, int height, int fps) async {
    await _channel.invokeMethod('setResolution', {'width': width, 'height': height, 'fps': fps});
  }

  Future<void> setHDR(bool enabled) async {
    await _channel.invokeMethod('setHDR', enabled);
  }

  Future<void> setExposure(double bias) async {
    await _channel.invokeMethod('setExposure', bias);
  }

  Future<void> setFocusPoint(double x, double y) async {
    await _channel.invokeMethod('setFocusPoint', {'x': x, 'y': y});
  }

  Stream<String> get errorStream {
    // Ideally we would set up an EventChannel for errors, but for simplicity
    // we can use setMethodCallHandler if we want to listen to errors from native.
    // Given the current implementation, we just catch the errors directly on the calls.
    return const Stream.empty();
  }

  Future<double> switchCamera() async {
    try {
      final newMaxZoom = await _channel.invokeMethod<double>('switchCamera');
      return newMaxZoom ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  Future<void> toggleTorch(bool enabled) async {
    await _channel.invokeMethod('toggleTorch', enabled);
  }

  Future<double> getScreenBrightness() async {
    try {
      final res = await _channel.invokeMethod<double>('getScreenBrightness');
      return res ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  Future<void> setScreenBrightness(double level) async {
    await _channel.invokeMethod('setScreenBrightness', level);
  }

}
