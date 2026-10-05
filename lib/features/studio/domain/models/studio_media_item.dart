import 'dart:io';

class StudioMediaItem {
  final String path;
  final bool isVideo;
  final DateTime createdAt;
  final String? thumbnailPath;

  StudioMediaItem({
    required this.path,
    required this.isVideo,
    required this.createdAt,
    this.thumbnailPath,
  });

  File get file => File(path);
  File? get thumbnailFile => thumbnailPath != null ? File(thumbnailPath!) : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioMediaItem && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
