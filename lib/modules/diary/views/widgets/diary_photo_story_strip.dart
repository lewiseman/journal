import 'dart:io';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';

/// A saved photo story's prints on the diary page, in their saved order.
class DiaryPhotoStoryStrip extends StatelessWidget {
  const DiaryPhotoStoryStrip({super.key, required this.item, this.onOpen});

  final DiaryItem item;

  /// Null on static previews and page curls.
  final VoidCallback? onOpen;

  static const _shown = 4;

  @override
  Widget build(BuildContext context) {
    final photos = item.photos;
    final extra = photos.length - _shown;
    final strip = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (index, photo) in photos.take(_shown).indexed)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox.square(
              dimension: 72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _StoredPhoto(path: photo.path),
                  if (index == _shown - 1 && extra > 0)
                    ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Text(
                          '+$extra',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
    final count = '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}';
    return Semantics(
      button: onOpen != null,
      label: 'Photo story, $count',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('diary-photo-story-${item.itemUuid}'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: strip,
        ),
      ),
    );
  }
}

class _StoredPhoto extends StatefulWidget {
  const _StoredPhoto({required this.path});
  final String path;

  @override
  State<_StoredPhoto> createState() => _StoredPhotoState();
}

class _StoredPhotoState extends State<_StoredPhoto> {
  late Future<File?> _file = DiaryPhotoStore.instance.resolve(widget.path);

  @override
  void didUpdateWidget(_StoredPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _file = DiaryPhotoStore.instance.resolve(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done) {
        return ColoredBox(color: context.colors.surfaceContainer);
      }
      if (file == null) return const DiaryMissingPhoto();
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 216,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const DiaryMissingPhoto(),
      );
    },
  );
}
