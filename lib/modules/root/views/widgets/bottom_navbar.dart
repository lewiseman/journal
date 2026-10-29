import 'package:flutter/services.dart';
import 'package:journal/common.dart';

const _destinations = [
  (
    label: 'Diary',
    image: 'assets/images/navigation/diary_inactive.png',
    selectedImage: 'assets/images/navigation/diary_active.png',
  ),
  (
    label: 'Notes',
    image: 'assets/images/navigation/notes_inactive.png',
    selectedImage: 'assets/images/navigation/notes_active.png',
  ),
  (
    label: 'Flow',
    image: 'assets/images/navigation/flow_inactive.png',
    selectedImage: 'assets/images/navigation/flow_active.png',
  ),
  (
    label: 'More',
    image: 'assets/images/navigation/more_inactive.png',
    selectedImage: 'assets/images/navigation/more_active.png',
  ),
];

class JournalBottomNavbar extends StatelessWidget {
  const new({required this.selectedIndex, required this.onSelected, super.key});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _maxContentWidth = 700.0;
  static const _sidePadding = 12.0;

  void _select(int index) {
    if (index == selectedIndex) return;
    HapticFeedback.selectionClick();
    onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
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
                      dark: context.colors.brightness == Brightness.dark,
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
                          child: _NavigationDestination(
                            label: _destinations[index].label,
                            image: _destinations[index].image,
                            selectedImage: _destinations[index].selectedImage,
                            selected: index == selectedIndex,
                            onSelected: () => _select(index),
                          ),
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
}

class _NavigationDestination extends StatefulWidget {
  const _NavigationDestination({
    required this.label,
    required this.image,
    required this.selectedImage,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String image;
  final String selectedImage;
  final bool selected;
  final VoidCallback onSelected;

  @override
  State<_NavigationDestination> createState() => _NavigationDestinationState();
}

class _NavigationDestinationState extends State<_NavigationDestination> {
  bool _pressed = false;

  void _highlight(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final color = widget.selected
        ? context.colors.primary
        : context.colors.onSurfaceVariant;
    return Semantics(
      selected: widget.selected,
      button: true,
      label: '${widget.label} tab',
      onTap: widget.onSelected,
      excludeSemantics: true,
      child: InkWell(
        excludeFromSemantics: true,
        enableFeedback: false,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onHighlightChanged: _highlight,
        onTap: widget.onSelected,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 44,
                child: AnimatedScale(
                  scale: _pressed ? .94 : 1,
                  duration: reduced
                      ? Duration.zero
                      : Duration(milliseconds: _pressed ? 70 : 140),
                  curve: Curves.easeOutCubic,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: widget.selected ? 1 : 0),
                    duration: reduced
                        ? Duration.zero
                        : Duration(milliseconds: widget.selected ? 320 : 180),
                    curve: widget.selected
                        ? Curves.easeOutBack
                        : Curves.easeOutCubic,
                    builder: (context, selection, child) => Transform.translate(
                      offset: Offset(0, -3 * selection),
                      child: Transform.scale(
                        scale: .82 + .24 * selection,
                        child: child,
                      ),
                    ),
                    // Mount both states ahead of selection to keep the
                    // artwork available throughout the lift and crossfade.
                    child: AnimatedCrossFade(
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      firstCurve: Curves.easeOutCubic,
                      secondCurve: Curves.easeOutCubic,
                      crossFadeState: widget.selected
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: Image.asset(
                        widget.image,
                        width: 44,
                        height: 44,
                        excludeFromSemantics: true,
                      ),
                      secondChild: Image.asset(
                        widget.selectedImage,
                        width: 44,
                        height: 44,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                style: DefaultTextStyle.of(context).style.copyWith(
                  color: color,
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: widget.selected
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(widget.label, maxLines: 1),
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
    required this.dark,
    required this.destinationCount,
    required this.insets,
    required this.textDirection,
  });

  final double position;
  final Color accent;
  final bool dark;
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

    // Compensate for accents with less contrast against the current surface.
    final luminance = accent.computeLuminance();
    final contrast = dark ? luminance : 1 - luminance;
    final glowOpacity = (dark ? .44 : .34) + (1 - contrast) * .18;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, -8),
        width: itemWidth * 1.5,
        height: 50,
      ),
      Paint()
        ..color = accent.withValues(alpha: glowOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, -2),
        width: itemWidth * .95,
        height: 16,
      ),
      Paint()
        ..color = accent.withValues(alpha: glowOpacity * .82)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final rim = Rect.fromLTWH(
      centerX - itemWidth * .625,
      0,
      itemWidth * 1.25,
      1.2,
    );
    final shader = LinearGradient(
      colors: [
        accent.withValues(alpha: 0),
        accent.withValues(alpha: glowOpacity + .18),
        Color.lerp(
          accent,
          Colors.white,
          dark ? .3 : .08,
        )!.withValues(alpha: dark ? .95 : .88),
        accent.withValues(alpha: glowOpacity + .18),
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
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawLine(
      rimStart,
      rimEnd,
      Paint()
        ..shader = shader
        ..strokeWidth = 1.4,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavigationEdgeGlowPainter oldDelegate) =>
      position != oldDelegate.position ||
      accent != oldDelegate.accent ||
      dark != oldDelegate.dark ||
      destinationCount != oldDelegate.destinationCount ||
      insets != oldDelegate.insets ||
      textDirection != oldDelegate.textDirection;
}
