import 'dart:math' as math;

import 'package:intl/intl.dart' show DateFormat;
import 'package:journal/common.dart';

const _papers = [
  NoteColorPreset.sand,
  NoteColorPreset.lavender,
  NoteColorPreset.sage,
  NoteColorPreset.rose,
  NoteColorPreset.sky,
  NoteColorPreset.paper,
];

int _paperIndex(ThoughtEntity thought) => thought.uuid.codeUnits.fold(
  0,
  (sum, unit) => (sum + unit) % _papers.length,
);

NoteColors flowThoughtColors(ThoughtEntity thought, ColorScheme colors) =>
    _papers[_paperIndex(thought)].resolveColors(colors);

String flowThoughtDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return DateFormat(date.year == now.year ? 'MMM d' : 'MMM d, y').format(date);
}

class FlowThoughtCard extends StatelessWidget {
  const FlowThoughtCard({
    super.key,
    required this.thought,
    required this.onTap,
  });

  final ThoughtEntity thought;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = flowThoughtColors(thought, context.colors);
    final background = Color.lerp(
      colors.background,
      context.colors.surface,
      .16,
    )!;
    final shape = FlowCloudBorder(
      alternate: _paperIndex(thought).isOdd,
      side: BorderSide(
        // Preserve a visible seam when clouds with identical fills overlap.
        color: colors.foreground.withValues(alpha: context.isDark ? .16 : .12),
        width: 1,
      ),
    );
    final date = flowThoughtDate(thought.createdAt);
    return Semantics(
      button: true,
      label: '$date. ${thought.content}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: background,
        elevation: 4,
        shadowColor: context.colors.shadow.withValues(
          alpha: context.isDark ? .38 : .20,
        ),
        surfaceTintColor: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(background, Colors.white, .1)!, background],
            ),
          ),
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onTap,
            customBorder: shape,
            splashColor: colors.foreground.withValues(alpha: .06),
            highlightColor: colors.foreground.withValues(alpha: .025),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final tail = shape.tailFor(constraints.biggest);
                final bodyHeight = constraints.maxHeight - tail;
                final compact = bodyHeight < 90 * scale;
                final small = bodyHeight < 160 * scale;
                final padding = compact ? 10.0 : (small ? 14.0 : 16.0);
                // Keep ink inside the scallops as cards grow for larger text.
                final horizontalPadding = math.max(
                  padding + 4,
                  constraints.maxWidth * .12,
                );
                final verticalPadding = math.max(padding, bodyHeight * .12);
                final fontSize = compact ? 14.0 : (small ? 15.0 : 16.0);
                final lineHeight =
                    MediaQuery.textScalerOf(context).scale(fontSize) * 1.4;
                final metadataHeight = compact ? 0.0 : 20 * scale;
                final lines = math.max(
                  1,
                  ((bodyHeight - verticalPadding * 2 - metadataHeight) /
                          lineHeight)
                      .floor(),
                );
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    verticalPadding,
                    horizontalPadding,
                    verticalPadding + tail,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          thought.content,
                          maxLines: lines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.foreground,
                            fontSize: fontSize,
                            height: 1.4,
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 8),
                        Text(
                          date,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            color: colors.secondary.withValues(alpha: .65),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One cloud outline serves the fill, shadow, clipping and touch feedback.
class FlowCloudBorder extends OutlinedBorder {
  const FlowCloudBorder({
    super.side,
    required this.alternate,
    this.tailHeight = 18,
  });

  final bool alternate;
  final double tailHeight;

  // A fixed twelve-curve silhouette, built once. Scaling this path avoids
  // combining overlapping circles or generating bumps during scrolling.
  static final _cloud = Path()
    ..moveTo(.075, .17)
    ..cubicTo(.025, .035, .17, .005, .25, .075)
    ..cubicTo(.28, 0, .46, 0, .51, .08)
    ..cubicTo(.61, 0, .79, 0, .82, .09)
    ..cubicTo(.925, .025, 1, .105, .95, .22)
    ..cubicTo(1, .25, 1, .42, .94, .47)
    ..cubicTo(1, .53, 1, .715, .935, .75)
    ..cubicTo(.99, .875, .9, .99, .79, .93)
    ..cubicTo(.75, 1, .56, 1, .50, .94)
    ..cubicTo(.40, 1, .21, 1, .18, .92)
    ..cubicTo(.075, .98, 0, .87, .06, .76)
    ..cubicTo(0, .7, 0, .525, .06, .47)
    ..cubicTo(0, .355, .005, .19, .075, .17)
    ..close();

  double tailFor(Size size) => math.min(tailHeight, size.height * .28);

  Path _path(Rect rect, double inset) {
    final tail = tailFor(rect.size);
    final body = Rect.fromLTRB(
      rect.left + inset,
      rect.top + inset,
      rect.right - inset,
      rect.bottom - tail - inset,
    );
    final x = rect.left + rect.width * (alternate ? .26 : .74);
    final direction = alternate ? -1 : 1;
    final transform = Matrix4.diagonal3Values(
      body.width * (alternate ? -1 : 1),
      body.height,
      1,
    )..setTranslationRaw(alternate ? body.right : body.left, body.top, 0);
    return _cloud.transform(transform.storage)
      ..addOval(
        Rect.fromCircle(
          center: Offset(x, rect.bottom - tail * .68),
          radius: math.max(0, tail * .25 - inset),
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(x + direction * tail * .55, rect.bottom - tail * .15),
          radius: math.max(0, tail * .14 - inset),
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, 0);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, side.strokeInset);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty || side.style == BorderStyle.none) return;
    final border = getOuterPath(rect)
      ..fillType = PathFillType.evenOdd
      ..addPath(getInnerPath(rect), Offset.zero);
    canvas.drawPath(border, Paint()..color = side.color);
  }

  @override
  FlowCloudBorder copyWith({BorderSide? side}) => FlowCloudBorder(
    side: side ?? this.side,
    alternate: alternate,
    tailHeight: tailHeight,
  );

  @override
  ShapeBorder scale(double t) => FlowCloudBorder(
    side: side.scale(t),
    alternate: alternate,
    tailHeight: tailHeight * t,
  );

  @override
  bool operator ==(Object other) =>
      other is FlowCloudBorder &&
      other.side == side &&
      other.alternate == alternate &&
      other.tailHeight == tailHeight;

  @override
  int get hashCode => Object.hash(side, alternate, tailHeight);
}
