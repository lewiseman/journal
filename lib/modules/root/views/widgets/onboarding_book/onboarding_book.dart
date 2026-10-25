import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'book_paper.dart';
import 'book_fold.dart';
import 'book_materials.dart';

const _ink = Color(0xFF30274E);
const onboardingSpreadAspectRatio = 4 / 3;
const onboardingCoverAsset = 'assets/images/onboarding/cover.webp';

// Match decoding to the displayed spread, with a cap at the source resolution.
// Both leaves use the same provider and share one decoded image in the cache.
int onboardingImageCacheWidth(double bookWidth, double pixelRatio) =>
    ((bookWidth - 12) * pixelRatio).ceil().clamp(1, 1448);

ImageProvider onboardingArtworkProvider(String asset, int cacheWidth) =>
    ResizeImage(AssetImage(asset), width: cacheWidth);

const onboardingFeatures = [
  (
    name: 'Notes',
    artwork: 'assets/images/onboarding/notes.webp',
    scene: 'Notes with a tiny idea and a reminder to take the scenic route.',
    title: 'Catch a\nthought.',
    detail: 'Little ideas.\nEndless possibilities.',
    accent: Color(0xFF517E71),
  ),
  (
    name: 'Diary',
    artwork: 'assets/images/onboarding/diary.webp',
    scene:
        'A sunny diary entry and coffee by a window. Today felt like sunshine.',
    title: 'Keep the\nmoments.',
    detail: 'The ordinary days.\nThe unforgettable ones.',
    accent: Color(0xFFA46D63),
  ),
  (
    name: 'AI',
    artwork: 'assets/images/onboarding/ai.webp',
    scene: 'Writing prompts: Where do I begin? What made you smile today?',
    title: 'Find your\nnext thought.',
    detail: 'A little inspiration,\nwhenever you need it.',
    accent: Color(0xFF8265B0),
  ),
  (
    name: 'Tasks',
    artwork: 'assets/images/onboarding/tasks.webp',
    scene: 'A gentler to-do: Make time for me. Get some fresh air. Start something new. One thing at a time.',
    title: 'Make room\nfor what\nmatters.',
    detail: 'Small steps.\nA little more clarity.',
    accent: Color(0xFF587BA0),
  ),
  (
    name: 'Birthdays',
    artwork: 'assets/images/onboarding/birthdays.webp',
    scene: 'June 12, Maya’s birthday. Make a little magic.',
    title: 'Remember\nyour people.',
    detail: 'Their special days,\nheld close.',
    accent: Color(0xFFAF6F84),
  ),
  (
    name: 'Movies',
    artwork: 'assets/images/onboarding/movies.webp',
    scene:
        'After the Sun, an illustrated movie poster and a movie night ticket.',
    title: 'Save your\nnext movie\nnight.',
    detail: 'Stories to get lost in.\nAll in one place.',
    accent: Color(0xFFAA8146),
  ),
];

class OnboardingBook extends StatelessWidget {
  const OnboardingBook({
    super.key,
    required this.page,
    required this.direction,
    required this.turn,
    required this.closing,
    required this.nameController,
    required this.nameFocus,
    required this.editable,
    required this.onSubmit,
    this.onPageTap,
    this.artworkWidth,
  });
  final int page, direction;
  final double turn, closing;
  final double? artworkWidth;
  final TextEditingController nameController;
  final FocusNode nameFocus;
  final bool editable;
  final VoidCallback onSubmit;
  final ValueChanged<int>? onPageTap;

  @override
  Widget build(BuildContext context) => BookMaterials(
    builder: (context, paperTexture, bindingTexture) => LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth - 12;
        final leaf = full / 2;
        final h = constraints.maxHeight - 20;
        final fold = BookFoldGeometry(
          leafSize: Size(leaf, h),
          progress: closing.clamp(0.0, 1.0),
        );
        final pageProgress = (page + direction * turn) / 5;
        final leftDepth = 9 + 7 * pageProgress;
        final cacheWidth = onboardingImageCacheWidth(
          artworkWidth ?? constraints.maxWidth,
          MediaQuery.devicePixelRatioOf(context),
        );
        Widget sheet(int index, bool left) => _Leaf(
          index: index.clamp(0, 5),
          left: left,
          cacheWidth: cacheWidth,
          onTap:
              onPageTap != null &&
                  (left ? page > 0 : page < onboardingFeatures.length - 1)
              ? () => onPageTap!(left ? -1 : 1)
              : null,
        );
        Widget positioned(double left, Widget child) => Positioned(
          left: left,
          top: 4,
          width: leaf,
          height: h,
          child: child,
        );
        final next = (page + direction).clamp(0, 5);
        final inside = CustomPaint(
          painter: BookLeafStack(
            left: true,
            depth: leftDepth,
            paperTexture: paperTexture,
            bindingTexture: bindingTexture,
            board: true,
          ),
          child: sheet(turn > 0 && direction == -1 ? next : page, true),
        );
        final outside = _Cover(
          controller: nameController,
          focus: nameFocus,
          editable: editable,
          onSubmit: onSubmit,
        );
        final tilt = math.min(
          .10,
          math.max(0.0, MediaQuery.sizeOf(context).width - full - 10) /
              constraints.maxHeight,
        );
        // Leave room for the stronger open tilt, then settle to the original
        // cover size after folding. Framing stays fixed during the fold.
        final scale = .97 + .03 * fold.settleProgress;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, fold.perspective)
            ..rotateX(-.14 + .105 * fold.settleProgress)
            ..rotateY(.05 - .08 * fold.settleProgress)
            ..rotateZ(-tilt * (1 - fold.settleProgress))
            ..scaleByDouble(scale, scale, scale, 1),
          child: Transform.translate(
            // Only the fully closed book recenters. Its spine and back cover
            // stay anchored throughout the actual folding motion.
            offset: Offset(fold.recenter, 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      key: const ValueKey('book-stationary-case'),
                      painter: BookBoards(closing: fold.foldProgress),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: BookBinding(
                          progress: pageProgress,
                          closing: fold.foldProgress,
                          showLeft: false,
                          paperTexture: paperTexture,
                          bindingTexture: bindingTexture,
                        ),
                      ),
                    ),
                  ),
                  positioned(
                    leaf,
                    ExcludeSemantics(
                      excluding: fold.outsideVisible,
                      child: sheet(
                        turn > 0 && direction == 1 ? next : page,
                        false,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: BookFoldShadow(fold: fold)),
                    ),
                  ),
                  positioned(
                    0,
                    Transform(
                      key: const ValueKey('book-cover-hinge'),
                      transform: fold.visibleFaceTransform,
                      child: CustomPaint(
                        foregroundPainter: BookFoldEdge(fold: fold),
                        child: fold.outsideVisible ? outside : inside,
                      ),
                    ),
                  ),
                  if (closing == 0 && turn > 0)
                    positioned(
                      direction == 1 ? leaf : 0,
                      ExcludeSemantics(
                        child: BentBookPage(
                          progress: turn,
                          reverse: direction == -1,
                          front: sheet(page, direction == -1),
                          back: sheet(next, direction == 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _Leaf extends StatelessWidget {
  const _Leaf({
    required this.index,
    required this.left,
    required this.cacheWidth,
    this.onTap,
  });
  final int index;
  final bool left;
  final int cacheWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final feature = onboardingFeatures[index];
    return Semantics(
      image: true,
      onTap: onTap,
      hint: onTap == null ? null : (left ? 'Previous page' : 'Next page'),
      label: left
          ? '${feature.name}. ${feature.title.replaceAll('\n', ' ')} '
                '${feature.detail.replaceAll('\n', ' ')}'
          : feature.scene,
      child: GestureDetector(
        onTap: onTap,
        excludeFromSemantics: true,
        child: ClipPath(
          clipper: PaperEdge(left: left),
          child: CustomPaint(
            foregroundPainter: PaperLighting(left: left),
            child: ColoredBox(
              color: const Color(0xFFF5ECD6),
              child: LayoutBuilder(
                builder: (context, constraints) => OverflowBox(
                  alignment: left
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  minWidth: constraints.maxWidth * 2,
                  maxWidth: constraints.maxWidth * 2,
                  minHeight: constraints.maxHeight,
                  maxHeight: constraints.maxHeight,
                  child: Image(
                    image: onboardingArtworkProvider(
                      feature.artwork,
                      cacheWidth,
                    ),
                    // Geometry preserves the source's 4:3 ratio at rest. Each
                    // leaf clips exactly half; no content is cropped or mirrored.
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.controller,
    required this.focus,
    required this.editable,
    required this.onSubmit,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final bool editable;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const CoverBevel(),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFFAF99BF),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: Image(
                  // Keep one decoded cover as keyboard insets change its size.
                  image: const AssetImage(onboardingCoverAsset),
                  gaplessPlayback: true,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  semanticLabel: 'Journal. A journal by you. One of a kind, just like you.',
                ),
              ),
              Positioned(
                left: constraints.maxWidth * .16,
                right: constraints.maxWidth * .16,
                top: constraints.maxHeight * .55,
                height: constraints.maxHeight * .19,
                child: Center(
                  child: TextField(
                    controller: controller,
                    focusNode: focus,
                    enabled: editable,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [LengthLimitingTextInputFormatter(40)],
                    onSubmitted: (_) => onSubmit(),
                    style: TextStyle(
                      color: _ink,
                      fontSize: math.min(32, constraints.maxWidth * .13),
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1,
                    ),
                    cursorColor: _ink,
                    decoration: const InputDecoration(
                      hintText: 'you.',
                      hintStyle: TextStyle(color: Color(0xFF705B8D)),
                      semanticCounterText: 'Your name',
                      labelText: 'Your name',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      labelStyle: TextStyle(color: Color(0xFF705B8D)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class OnboardingSky extends StatelessWidget {
  const OnboardingSky({super.key});
  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22208B), Color(0xFF0D103F), Color(0xFF281377)],
        ),
      ),
      child: CustomPaint(painter: _SkyPainter()),
    ),
  );
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter();
  @override
  void paint(Canvas canvas, Size size) {
    for (final orb in [
      (Offset(size.width * .03, size.height * .32), const Color(0xFF68DCCD)),
      (Offset(size.width * .95, size.height * .87), const Color(0xFF9E60E6)),
    ]) {
      final rect = Rect.fromCircle(center: orb.$1, radius: size.width * .6);
      canvas.drawCircle(
        orb.$1,
        size.width * .6,
        Paint()
          ..shader = RadialGradient(
            colors: [
              orb.$2.withValues(alpha: .13),
              orb.$2.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    final random = math.Random(23);
    for (var i = 0; i < 22; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(
        point,
        i % 4 == 0 ? 1.8 : .8,
        Paint()
          ..color = const Color(0xFFDDD0FF)
              .withValues(alpha: .15 + random.nextDouble() * .25),
      );
    }
    final path = Path()
      ..moveTo(-40, size.height * .69)
      ..cubicTo(
        size.width * .3,
        size.height * .46,
        size.width * .8,
        size.height * .92,
        size.width + 40,
        size.height * .65,
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x227D6AD7),
    );
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => false;
}
