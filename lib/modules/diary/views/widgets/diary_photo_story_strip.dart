import 'dart:io';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';

/// A mounted print or overlapping notebook stack, shared by live and curl faces.
class DiaryPhotoStoryStrip extends StatelessWidget {
  const DiaryPhotoStoryStrip({super.key, required this.item, this.onOpen});

  final DiaryItem item;
  final VoidCallback? onOpen;

  static const shown = 2;
  // Stable cache keys across live/curl faces, sized for the prints at up to 2x.
  static const _singleDecode = 576, _backDecode = 384;

  double _angle(int index) {
    final seed = item.itemUuid.codeUnits.fold(0, (sum, code) => sum + code);
    return ((seed + index) % 2 == 0 ? -1 : 1) * .018;
  }

  @override
  Widget build(BuildContext context) {
    final photos = item.photos;
    if (photos.isEmpty) return const SizedBox.shrink();
    final extra = photos.length - shown;
    final count = '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}';
    return Semantics(
      button: onOpen != null,
      label: 'Photo story, $count',
      onTap: onOpen,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('diary-photo-story-${item.itemUuid}'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.only(
            top: 11,
            bottom: 24,
            left: 8,
            right: 10,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: photos.length == 1 ? 290 : 330,
              ),
              child: photos.length == 1
                  ? Transform.rotate(
                      angle: MediaQuery.textScalerOf(context).scale(1) >= 1.8
                          ? 0
                          : _angle(0),
                      child: _MountedPrint(
                        path: photos.first.path,
                        decodeSize: _singleDecode,
                        remaining: 0,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final inset = (constraints.maxWidth * .09).clamp(
                          12.0,
                          22.0,
                        );
                        final tilt =
                            MediaQuery.textScalerOf(context).scale(1) >= 1.8
                            ? 0.0
                            : 1.0;
                        final direction =
                            Directionality.of(context) == TextDirection.rtl
                            ? -1.0
                            : 1.0;
                        final paper = context.colors.surfaceContainerLowest;
                        return Stack(
                          key: ValueKey('diary-photo-stack-${item.itemUuid}'),
                          clipBehavior: Clip.none,
                          children: [
                            if (extra > 0)
                              PositionedDirectional(
                                top: 5,
                                bottom: 6,
                                start: inset * .45,
                                end: inset * .55,
                                child: Transform.rotate(
                                  angle: -.045 * tilt * direction,
                                  child: CustomPaint(
                                    painter: _PrintMount(
                                      paper: paper,
                                      ink: context.colors.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            PositionedDirectional(
                              top: 0,
                              start: inset,
                              end: 0,
                              child: Transform.rotate(
                                angle: .065 * tilt * direction,
                                child: _MountedPrint(
                                  path: photos[1].path,
                                  decodeSize: _backDecode,
                                  remaining: 0,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsetsDirectional.only(
                                top: 13,
                                end: inset,
                              ),
                              child: Transform.rotate(
                                angle: _angle(0) * tilt,
                                child: _MountedPrint(
                                  path: photos.first.path,
                                  decodeSize: _singleDecode,
                                  remaining: extra > 0 ? extra : 0,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MountedPrint extends StatelessWidget {
  const _MountedPrint({
    required this.path,
    required this.remaining,
    required this.decodeSize,
  });
  final String path;
  final int remaining, decodeSize;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PrintMount(
      paper: context.colors.surfaceContainerLowest,
      ink: context.colors.onSurface,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: _StoredPhoto(path: path, decodeSize: decodeSize),
          ),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  '+$remaining',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

class _PrintMount extends CustomPainter {
  const _PrintMount({required this.paper, required this.ink});
  final Color paper, ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect.shift(const Offset(1, 2)),
      Paint()..color = ink.withValues(alpha: .08),
    );
    canvas.drawRect(rect, Paint()..color = paper);
    canvas.drawRect(
      rect.deflate(.3),
      Paint()
        ..color = ink.withValues(alpha: .13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
  }

  @override
  bool shouldRepaint(_PrintMount oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

class _StoredPhoto extends StatefulWidget {
  const _StoredPhoto({required this.path, required this.decodeSize});
  final String path;
  final int decodeSize;

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
      return Image(
        image: ResizeImage(
          FileImage(file),
          width: widget.decodeSize,
          height: widget.decodeSize,
          policy: ResizeImagePolicy.fit,
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const DiaryMissingPhoto(),
      );
    },
  );
}
