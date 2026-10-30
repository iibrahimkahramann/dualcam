import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import '../../domain/models/studio_media_item.dart';
import '../providers/studio_provider.dart';

class PhotoEditorView extends ConsumerWidget {
  final StudioMediaItem item;

  const PhotoEditorView({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProImageEditor.file(
      item.file,
      configs: ProImageEditorConfigs(
        designMode: ImageEditorDesignMode.material,
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.yellow,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.yellow,
            secondary: Colors.yellowAccent,
            surface: Colors.black,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Colors.black,
            selectedItemColor: Colors.yellow,
            unselectedItemColor: Colors.white54,
          ),
        ),
        i18n: I18n(
          cancel: 'cancel'.tr(),
          undo: 'editor_undo'.tr(),
          redo: 'editor_redo'.tr(),
          done: 'editor_done'.tr(),
          remove: 'editor_remove'.tr(),
          textEditor: I18nTextEditor(
            bottomNavigationBarText: 'editor_text'.tr(),
            inputHintText: 'editor_text_hint'.tr(),
          ),
          paintEditor: I18nPaintEditor(
            bottomNavigationBarText: 'editor_paint'.tr(),
          ),
          cropRotateEditor: I18nCropRotateEditor(
            bottomNavigationBarText: 'editor_crop_rotate'.tr(),
          ),
          filterEditor: I18nFilterEditor(
            bottomNavigationBarText: 'editor_filters'.tr(),
          ),
          blurEditor: I18nBlurEditor(
            bottomNavigationBarText: 'editor_blur'.tr(),
          ),
        ),
      ),
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) async {
          // Save edited bytes over the original file or as a new file
          final file = item.file;
          await file.writeAsBytes(bytes);
          
          // Clear image cache so the UI reloads the new image from disk
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          
          ref.invalidate(studioMediaProvider);
          if (context.mounted) {
            Navigator.pop(context); // Close the editor
          }
        },
      ),
    );
  }
}
