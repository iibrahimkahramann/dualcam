import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path/path.dart' as p;
import '../../domain/models/studio_media_item.dart';

class StudioRepository {
  Future<Directory> _getStudioDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final studioDir = Directory('${docDir.path}/DualCamStudio');
    if (!await studioDir.exists()) {
      await studioDir.create(recursive: true);
    }
    return studioDir;
  }

  Future<List<StudioMediaItem>> saveMediaToStudio(List<String> tempPaths, bool isVideo) async {
    final studioDir = await _getStudioDirectory();
    List<StudioMediaItem> savedItems = [];

    for (String tempPath in tempPaths) {
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) continue;

      final extension = p.extension(tempPath);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(tempPath)}$extension';
      final newPath = '${studioDir.path}/$fileName';
      
      final savedFile = await tempFile.copy(newPath);
      String? thumbnailPath;

      if (isVideo) {
        try {
          final thumbFilePath = '${studioDir.path}/thumb_${p.basenameWithoutExtension(savedFile.path)}.jpg';
          thumbnailPath = await VideoThumbnail.thumbnailFile(
            video: savedFile.path,
            thumbnailPath: thumbFilePath,
            imageFormat: ImageFormat.JPEG,
            maxHeight: 512,
            quality: 75,
          );
        } catch (e) {
          debugPrint("Thumbnail generation error: $e");
        }
      }

      savedItems.add(StudioMediaItem(
        path: savedFile.path,
        isVideo: isVideo,
        createdAt: DateTime.now(),
        thumbnailPath: thumbnailPath,
      ));

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    return savedItems;
  }

  Future<List<StudioMediaItem>> getStudioMedia() async {
    final studioDir = await _getStudioDirectory();
    final List<StudioMediaItem> items = [];

    try {
      final entities = studioDir.listSync(recursive: false);
      
      for (var entity in entities) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          if (fileName.startsWith('thumb_')) continue;

          final ext = p.extension(entity.path).toLowerCase();
          final isVideo = ext == '.mp4' || ext == '.mov';
          final isImage = ext == '.jpg' || ext == '.jpeg' || ext == '.png';
          
          if (isVideo || isImage) {
            // Find if there's a matching thumbnail for video
            String? thumbPath;
            if (isVideo) {
              final thumbFile = File('${studioDir.path}/thumb_${p.basenameWithoutExtension(entity.path)}.jpg');
              if (thumbFile.existsSync()) thumbPath = thumbFile.path;
            }

            final stat = await entity.stat();
            items.add(StudioMediaItem(
              path: entity.path,
              isVideo: isVideo,
              createdAt: stat.changed,
              thumbnailPath: thumbPath,
            ));
          }
        }
      }
      
      // Sort by newest first
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint("Error fetching studio media: $e");
    }

    return items;
  }

  Future<void> deleteMedia(StudioMediaItem item) async {
    try {
      final file = File(item.path);
      if (await file.exists()) await file.delete();
      
      if (item.thumbnailPath != null) {
        final thumbFile = File(item.thumbnailPath!);
        if (await thumbFile.exists()) await thumbFile.delete();
      }
    } catch (e) {
      debugPrint("Error deleting media: $e");
    }
  }
}
