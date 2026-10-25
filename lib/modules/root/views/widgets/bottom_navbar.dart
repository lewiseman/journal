import 'package:flutter/cupertino.dart';
import 'package:journal/common.dart';

const _destinations = [
  (
    label: 'Diary',
    icon: CupertinoIcons.book,
    selectedIcon: CupertinoIcons.book_fill,
  ),
  (
    label: 'Notes',
    icon: CupertinoIcons.doc_text,
    selectedIcon: CupertinoIcons.doc_text_fill,
  ),
  (
    label: 'Flow',
    icon: CupertinoIcons.check_mark_circled,
    selectedIcon: CupertinoIcons.check_mark_circled_solid,
  ),
  (
    label: 'More',
    icon: CupertinoIcons.square_grid_2x2,
    selectedIcon: CupertinoIcons.square_grid_2x2_fill,
  ),
];

class JournalBottomNavbar extends StatelessWidget {
  const new({required this.selectedIndex, required this.onSelected, super.key});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _maxContentWidth = 700.0;
  static const _sidePadding = 12.0;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 200);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [context.colors.surfaceContainerLow, context.colors.surface],
        ),
        border: Border(
          top: BorderSide(color: context.colors.outlineVariant, width: 0.66),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: context.colors.primary),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, accent, _) => TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: selectedIndex.toDouble()),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, position, _) => CustomPaint(
                    painter: _NavigationEdgeGlowPainter(
                      position: position,
                      accent: accent!,
                      destinationCount: _destinations.length,
                      insets: MediaQuery.paddingOf(context),
                      textDirection: Directionality.of(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 8),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
                  child: Row(
                    children: [
                      for (var index = 0; index < _destinations.length; index++)
                        Expanded(
                          child: _buildDestination(context, index, duration),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestination(BuildContext context, int index, Duration duration) {
    final selected = index == selectedIndex;
    final destination = _destinations[index];
    final color = selected
        ? context.colors.primary
        : context.colors.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: '${destination.label} tab',
      onTap: () => onSelected(index),
      excludeSemantics: true,
      child: InkWell(
        excludeFromSemantics: true,
        splashColor: Colors.transparent,
        highlightColor: context.colors.primary.withValues(alpha: .08),
        onTap: () => onSelected(index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 28,
                child: AnimatedSwitcher(
                  duration: duration,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    key: ValueKey(selected),
                    size: 28,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: Curves.easeOut,
                style: DefaultTextStyle.of(context).style.copyWith(
                  color: color,
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(destination.label, maxLines: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationEdgeGlowPainter extends CustomPainter {
  const _NavigationEdgeGlowPainter({
    required this.position,
    required this.accent,
    required this.destinationCount,
    required this.insets,
    required this.textDirection,
  });

  final double position;
  final Color accent;
  final int destinationCount;
  final EdgeInsets insets;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final availableWidth = size.width - insets.horizontal;
    final contentWidth = availableWidth.clamp(
      0.0,
      JournalBottomNavbar._maxContentWidth,
    );
    final itemWidth =
        (contentWidth - 2 * JournalBottomNavbar._sidePadding) /
        destinationCount;
    if (itemWidth <= 0) return;
    final visualPosition = textDirection == TextDirection.rtl
        ? destinationCount - 1 - position
        : position;
    final centerX =
        insets.left +
        (availableWidth - contentWidth) / 2 +
        JournalBottomNavbar._sidePadding +
        itemWidth * (visualPosition + .5);

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // A light source just above the surface casts a shallow wash down the bar.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, -10),
        width: itemWidth * 1.9,
        height: 48,
      ),
      Paint()
        ..color = accent.withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, -3),
        width: itemWidth * 1.1,
        height: 16,
      ),
      Paint()
        ..color = accent.withValues(alpha: .4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    final rim = Rect.fromLTWH(
      centerX - itemWidth * .8,
      0,
      itemWidth * 1.6,
      1.2,
    );
    final shader = LinearGradient(
      colors: [
        accent.withValues(alpha: 0),
        accent.withValues(alpha: .55),
        Color.lerp(accent, Colors.white, .45)!,
        accent.withValues(alpha: .55),
        accent.withValues(alpha: 0),
      ],
      stops: const [0, .22, .5, .78, 1],
    ).createShader(rim);
    final rimStart = Offset(rim.left, .6);
    final rimEnd = Offset(rim.right, .6);
    canvas.drawLine(
      rimStart,
      rimEnd,
      Paint()
        ..shader = shader
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawLine(
      rimStart,
      rimEnd,
      Paint()
        ..shader = shader
        ..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavigationEdgeGlowPainter oldDelegate) =>
      position != oldDelegate.position ||
      accent != oldDelegate.accent ||
      destinationCount != oldDelegate.destinationCount ||
      insets != oldDelegate.insets ||
      textDirection != oldDelegate.textDirection;
}
