abstract class CameraRepository {
  /// Initializes the dual camera session.
  /// Throws an exception if permissions are denied or initialization fails.
  Future<void> initialize();

  /// Starts dual recording (Vertical and Horizontal).
  Future<void> startRecording();

  /// Stops recording and returns the paths of the recorded files.
  /// Result: [0] = Vertical Video Path, [1] = Horizontal Video Path
  Future<List<String>> stopRecording();

  /// Captures a photo and returns the paths of the saved images.
  /// Result: [0] = Vertical Photo, [1] = Horizontal Photo
  Future<List<String>> takePhoto();

  /// Disposes the camera session.
  Future<void> dispose();

  Future<List<Map<String, dynamic>>> getAvailableResolutions();
  Future<void> setResolution(int width, int height, int fps);
  Future<void> setHDR(bool enabled);
  Future<void> setExposure(double bias);
  Future<void> setFocusPoint(double x, double y);
  Future<double> getMaxZoom();
  Future<void> setZoom(double factor);
  Future<double> switchCamera();
  Future<void> toggleTorch(bool enabled);
  Future<double> getScreenBrightness();
  Future<void> setScreenBrightness(double level);
}
