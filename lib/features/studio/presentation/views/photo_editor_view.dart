import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        i18n: const I18n(
          cancel: 'İptal',
          undo: 'Geri Al',
          redo: 'Yinele',
          done: 'Bitti',
          remove: 'Kaldır',
          textEditor: I18nTextEditor(
            bottomNavigationBarText: 'Metin',
            inputHintText: 'Bir şeyler yazın...',
          ),
          paintEditor: I18nPaintEditor(bottomNavigationBarText: 'Çizim'),
          cropRotateEditor: I18nCropRotateEditor(
            bottomNavigationBarText: 'Kırp/Döndür',
          ),
          filterEditor: I18nFilterEditor(bottomNavigationBarText: 'Filtreler'),
          blurEditor: I18nBlurEditor(bottomNavigationBarText: 'Bulanıklık'),
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
