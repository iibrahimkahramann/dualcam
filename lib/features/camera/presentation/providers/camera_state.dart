class CameraState {
  final bool isInitialized;
  final bool isRecording;
  final bool isPhotoMode;
  final String? errorMessage;
  final List<String>? recordedFiles;

  const CameraState({
    this.isInitialized = false,
    this.isRecording = false,
    this.isPhotoMode = false,
    this.errorMessage,
    this.recordedFiles,
  });

  CameraState copyWith({
    bool? isInitialized,
    bool? isRecording,
    bool? isPhotoMode,
    String? errorMessage,
    List<String>? recordedFiles,
  }) {
    return CameraState(
      isInitialized: isInitialized ?? this.isInitialized,
      isRecording: isRecording ?? this.isRecording,
      isPhotoMode: isPhotoMode ?? this.isPhotoMode,
      errorMessage: errorMessage ?? this.errorMessage,
      recordedFiles: recordedFiles ?? this.recordedFiles,
    );
  }

  // To allow clearing the error message explicitly we can pass null 
  // but copyWith ignores nulls the way we wrote it.
  // We can add a specialized method or handle it softly.
  CameraState clearError() {
    return CameraState(
      isInitialized: isInitialized,
      isRecording: isRecording,
      isPhotoMode: isPhotoMode,
      errorMessage: null,
      recordedFiles: recordedFiles,
    );
  }
}
