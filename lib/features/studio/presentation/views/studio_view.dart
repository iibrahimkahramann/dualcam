import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/studio_provider.dart';
import 'media_preview_view.dart';
import 'dart:ui';

class StudioView extends ConsumerWidget {
  const StudioView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaAsync = ref.watch(studioMediaProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar.large(
            backgroundColor: Colors.black,
            stretch: true,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              'studio_title'.tr(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              ref.invalidate(studioMediaProvider);
              await ref.read(studioMediaProvider.future);
            },
          ),
          mediaAsync.when(
            skipLoadingOnReload: true,
            data: (items) {
              if (items.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.photo_on_rectangle, size: 80, color: Colors.white.withValues(alpha: 0.2)),
                        const SizedBox(height: 24),
                        Text(
                          'studio_empty_title'.tr(),
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'studio_empty_subtitle'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = items[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => MediaPreviewView(item: item),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                            ),
                          );
                        },
                        child: Hero(
                          tag: item.path,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (item.thumbnailFile != null)
                                  Image.file(item.thumbnailFile!, fit: BoxFit.cover)
                                else if (!item.isVideo)
                                  Image.file(item.file, fit: BoxFit.cover)
                                else
                                  Container(color: Colors.grey.shade900),
                                
                                if (item.isVideo)
                                  Positioned(
                                    bottom: 6,
                                    right: 6,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          color: Colors.black.withValues(alpha: 0.4),
                                          child: const Icon(
                                            CupertinoIcons.play_fill,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Colors.yellow)),
            ),
            error: (err, _) => SliverFillRemaining(
              child: Center(child: Text("\${'studio_error'.tr()} $err", style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
      ),
    );
  }
}
