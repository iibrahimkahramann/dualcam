import '../../domain/repositories/camera_repository.dart';
import '../datasources/camera_native_datasource.dart';

class CameraRepositoryImpl implements CameraRepository {
  final CameraNativeDataSource _dataSource;

  CameraRepositoryImpl(this._dataSource);

  @override
  Future<void> initialize() {
    return _dataSource.initialize();
  }

  @override
  Future<void> startRecording() {
    return _dataSource.startRecording();
  }

  @override
  Future<List<String>> stopRecording() {
    return _dataSource.stopRecording();
  }

  @override
  Future<List<String>> takePhoto() {
    return _dataSource.takePhoto();
  }

  @override
  Future<void> dispose() {
    return _dataSource.dispose();
  }

  @override
  Future<List<Map<String, dynamic>>> getAvailableResolutions() {
    return _dataSource.getAvailableResolutions();
  }

  @override
  Future<void> setResolution(int width, int height, int fps) {
    return _dataSource.setResolution(width, height, fps);
  }

  @override
  Future<void> setHDR(bool enabled) {
    return _dataSource.setHDR(enabled);
  }

  @override
  Future<void> setExposure(double bias) {
    return _dataSource.setExposure(bias);
  }

  @override
  Future<void> setFocusPoint(double x, double y) {
    return _dataSource.setFocusPoint(x, y);
  }

  @override
  Future<double> getMaxZoom() {
    return _dataSource.getMaxZoom();
  }

  @override
  Future<void> setZoom(double factor) {
    return _dataSource.setZoom(factor);
  }

  @override
  Future<double> switchCamera() {
    return _dataSource.switchCamera();
  }

  @override
  Future<void> toggleTorch(bool enabled) {
    return _dataSource.toggleTorch(enabled);
  }

  @override
  Future<double> getScreenBrightness() {
    return _dataSource.getScreenBrightness();
  }

  @override
  Future<void> setScreenBrightness(double level) {
    return _dataSource.setScreenBrightness(level);
  }
}
