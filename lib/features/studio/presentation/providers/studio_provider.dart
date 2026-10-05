import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/studio_repository.dart';
import '../../domain/models/studio_media_item.dart';

final studioRepositoryProvider = Provider<StudioRepository>((ref) {
  return StudioRepository();
});

final studioMediaProvider = FutureProvider<List<StudioMediaItem>>((ref) async {
  final repo = ref.watch(studioRepositoryProvider);
  return await repo.getStudioMedia();
});
