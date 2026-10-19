import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';
import '../../domain/models/studio_media_item.dart';
import '../../../../providers/premium/premium_provider.dart';
import '../../../../providers/rc/rc_placement_provider.dart';
import '../providers/studio_provider.dart';
import 'photo_editor_view.dart';

final videoControllerProvider = FutureProvider.autoDispose
    .family<VideoPlayerController, StudioMediaItem>((ref, item) async {
      if (!item.isVideo) throw Exception("Not a video");
      final controller = VideoPlayerController.file(item.file);
      try {
        await controller.initialize().timeout(const Duration(seconds: 8));
        controller.setLooping(true);
        controller.play();
      } catch (e) {
        controller.dispose();
        rethrow;
      }

      ref.onDispose(() {
        controller.dispose();
      });

      return controller;
    });

class MediaPreviewView extends ConsumerWidget {
  final StudioMediaItem item;

  const MediaPreviewView({super.key, required this.item});

  void _exportMedia(BuildContext context, WidgetRef ref) async {
    final isPremium = ref.read(isPremiumProvider);
    if (!isPremium) {
      showPaywallWithPlacement('default', 'premium');
      return;
    }

    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      if (item.isVideo) {
        await Gal.putVideo(item.path);
      } else {
        await Gal.putImage(item.path);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('studio_saved_to_gallery'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('studio_error'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _deleteMedia(BuildContext context, WidgetRef ref) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('studio_delete_confirm_title'.tr()),
        content: Text('studio_delete_confirm_content'.tr()),
        actions: [
          CupertinoDialogAction(
            child: Text('studio_cancel'.tr()),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text('studio_delete'.tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final repo = ref.read(studioRepositoryProvider);
      await repo.deleteMedia(item);
      ref.invalidate(studioMediaProvider);
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);

    // Watch the gallery state. If the item is edited and the gallery is invalidated,
    // this view will rebuild with the updated file stats (like a new modified date).
    final studioState = ref.watch(studioMediaProvider);
    final currentItem =
        studioState.value?.firstWhere(
          (m) => m.path == item.path,
          orElse: () => item,
        ) ??
        item;

    AsyncValue<VideoPlayerController>? videoAsync;
    if (currentItem.isVideo) {
      videoAsync = ref.watch(videoControllerProvider(currentItem));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      // No extendBody features, keeping Top and Bottom bars solid
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'studio_preview'.tr(),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          // Edit Button (Only for Photos)
          if (!currentItem.isVideo)
            IconButton(
              icon: const Icon(CupertinoIcons.pencil, color: Colors.yellow),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PhotoEditorView(item: currentItem),
                  ),
                );
              },
            ),

          // Mute Button for Videos
          if (currentItem.isVideo && videoAsync != null)
            videoAsync.maybeWhen(
              skipLoadingOnReload: false,
              data: (controller) => ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  final isMuted = value.volume == 0.0;
                  return IconButton(
                    icon: Icon(
                      isMuted
                          ? CupertinoIcons.speaker_slash_fill
                          : CupertinoIcons.speaker_2_fill,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      controller.setVolume(isMuted ? 1.0 : 0.0);
                    },
                  );
                },
              ),
              orElse: () => const SizedBox.shrink(),
            ),

          // Delete Button
          IconButton(
            icon: const Icon(CupertinoIcons.trash, color: Colors.redAccent),
            onPressed: () => _deleteMedia(context, ref),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Media Display fits perfectly between AppBar and BottomNavigationBar
          Hero(
            tag: currentItem.path,
            child: Center(
              child: currentItem.isVideo && videoAsync != null
                  ? videoAsync.when(
                      skipLoadingOnReload: true,
                      data: (controller) =>
                          _VideoPlayerWithControls(controller: controller),
                      loading: () =>
                          const CircularProgressIndicator(color: Colors.yellow),
                      error: (err, _) => Text(
                        "\${'studio_error'.tr()} $err",
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: SizedBox.expand(
                        child: Image.file(
                          currentItem.file,
                          // Use modified date as key so Flutter knows to redraw it after edit
                          key: ValueKey(
                            currentItem.createdAt.millisecondsSinceEpoch,
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
            ),
          ),

          // Watermark Overlay for Free Users
          if (!isPremium)
            IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.05),
                child: Center(
                  child: Transform.rotate(
                    angle: -0.5,
                    child: const Text(
                      "DUALCAM PRO",
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 60,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: isPremium ? Colors.white : Colors.yellow,
            borderRadius: BorderRadius.circular(100),
            onPressed: () => _exportMedia(context, ref),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPremium
                      ? CupertinoIcons.arrow_down_to_line
                      : CupertinoIcons.lock_fill,
                  color: Colors.black,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isPremium
                      ? 'studio_save_gallery'.tr()
                      : 'studio_save_watermark_free'.tr(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Custom Video Player with Interactive Controls
class _VideoPlayerWithControls extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoPlayerWithControls({required this.controller});

  @override
  State<_VideoPlayerWithControls> createState() =>
      _VideoPlayerWithControlsState();
}

class _VideoPlayerWithControlsState extends State<_VideoPlayerWithControls> {
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerWithControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _togglePlayPause() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
        _showControls = true;
      } else {
        widget.controller.play();
        _showControls = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background to prevent white flashes
          Container(color: Colors.black),

          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: widget.controller.value.size.width,
                height: widget.controller.value.size.height,
                child: VideoPlayer(widget.controller),
              ),
            ),
          ),

          // Play/Pause Center Overlay
          if (_showControls || !widget.controller.value.isPlaying)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.controller.value.isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                color: Colors.white,
                size: 50,
              ),
            ),

          // Bottom Progress Bar
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: VideoProgressIndicator(
                  widget.controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.yellow,
                    bufferedColor: Colors.white30,
                    backgroundColor: Colors.white10,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
