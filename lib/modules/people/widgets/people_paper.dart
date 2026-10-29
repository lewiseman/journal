import 'dart:math';

import 'package:flutter/material.dart';
import 'package:journal/config/diary_typography.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';

/// Stationery colours shared by every People page: warm desk, cream paper,
/// brown ink and a red wax seal.
@immutable
class PeoplePalette {
  const PeoplePalette._({
    required this.desk,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.clay,
    required this.wax,
    required this.rule,
  });

  static const _light = PeoplePalette._(
    desk: Color(0xFFF2E9DA),
    paper: Color(0xFFFCF7EE),
    ink: Color(0xFF3A2E28),
    muted: Color(0xFF8A7768),
    clay: Color(0xFF9B6456),
    wax: Color(0xFFA8322D),
    rule: Color(0x1F3A2E28),
  );
  static const _dark = PeoplePalette._(
    desk: Color(0xFF1C1815),
    paper: Color(0xFF2A241F),
    ink: Color(0xFFEDE2D2),
    muted: Color(0xFFA8998A),
    clay: Color(0xFFE6B4A7),
    wax: Color(0xFFC9473F),
    rule: Color(0x1FEDE2D2),
  );

  static PeoplePalette of(BuildContext context) =>
      context.isDark ? _dark : _light;

  final Color desk, paper, ink, muted, clay, wax, rule;

  static const charColor = Color(0xFF1E140E);
  static const scorchColor = Color(0xFF7A4A1E);
}

TextStyle peopleHand(BuildContext context, {double size = 30, Color? color}) =>
    DiaryTypography.of(context).title.copyWith(
      fontSize: size,
      height: 1.1,
      color: color ?? PeoplePalette.of(context).ink,
    );

TextStyle peopleSerif(BuildContext context, {double? size, Color? color}) =>
    DiaryTypography.of(context).body.copyWith(
      fontSize: size,
      color: color ?? PeoplePalette.of(context).ink,
    );

/// The common page frame: a desk-coloured background, a quiet app bar with
/// a handwritten title and a centred, width-limited column.
class PeopleScaffold extends StatelessWidget {
  const PeopleScaffold({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 40),
  });
  final String title;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    return QvacAssistantPage(
      enabled: false,
      child: Scaffold(
        backgroundColor: palette.desk,
        appBar: AppBar(
          backgroundColor: palette.desk,
          surfaceTintColor: Colors.transparent,
          foregroundColor: palette.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(title, style: peopleHand(context, size: 28)),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: ListView(padding: padding, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sheet of cream paper with a soft shadow, a faint fibre texture and,
/// optionally, ruled lines with a margin like a letter pad.
class PaperSheet extends StatelessWidget {
  const PaperSheet({
    super.key,
    required this.child,
    this.ruled = false,
    this.lineHeight = 30,
    this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 24),
    this.tilt = 0,
    this.shadow = true,
  });
  final Widget child;
  final bool ruled;
  final double lineHeight;
  final EdgeInsets padding;
  final double tilt;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    Widget sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paper,
        borderRadius: BorderRadius.circular(6),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: context.isDark ? .35 : .09,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: context.isDark ? .25 : .05,
                  ),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: _PaperPainter(
          rule: ruled ? palette.rule : null,
          margin: ruled ? palette.wax.withValues(alpha: .25) : null,
          lineHeight: lineHeight,
          top: padding.top,
          fibre: palette.ink.withValues(alpha: .025),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (tilt != 0) sheet = Transform.rotate(angle: tilt, child: sheet);
    return sheet;
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter({
    required this.rule,
    required this.margin,
    required this.lineHeight,
    required this.top,
    required this.fibre,
  });
  final Color? rule, margin;
  final double lineHeight, top;
  final Color fibre;

  @override
  void paint(Canvas canvas, Size size) {
    // Short random fibres give the paper some tooth without an image asset.
    final random = Random(7);
    final fibres = Paint()
      ..color = fibre
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final count = (size.width * size.height / 900).clamp(0, 400).toInt();
    for (var i = 0; i < count; i++) {
      final start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final angle = random.nextDouble() * pi;
      final length = 3 + random.nextDouble() * 6;
      canvas.drawLine(
        start,
        start + Offset(cos(angle), sin(angle)) * length,
        fibres,
      );
    }
    if (rule != null) {
      final line = Paint()
        ..color = rule!
        ..strokeWidth = 1;
      for (var y = top + lineHeight - 4; y < size.height - 8; y += lineHeight) {
        canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), line);
      }
    }
    if (margin != null) {
      canvas.drawLine(
        const Offset(16, 0),
        Offset(16, size.height),
        Paint()
          ..color = margin!
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      old.rule != rule ||
      old.margin != margin ||
      old.lineHeight != lineHeight ||
      old.top != top ||
      old.fibre != fibre;
}

/// A small rounded label, used for status and reading time.
class PeopleChip extends StatelessWidget {
  const PeopleChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.trailing,
  });
  final String label;
  final Widget? icon;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    final tint = color ?? palette.clay;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: tint.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: tint, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}

/// A tiny hand-drawn flame, for reading-time hints.
class FlameIcon extends StatelessWidget {
  const FlameIcon({super.key, this.size = 16, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FlamePainter(color ?? const Color(0xFFE0782A)),
  );
}

class _FlamePainter extends CustomPainter {
  const _FlamePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outer = Path()
      ..moveTo(w * .5, 0)
      ..cubicTo(w * .62, h * .28, w * .95, h * .42, w * .9, h * .7)
      ..cubicTo(w * .86, h * .92, w * .68, h, w * .5, h)
      ..cubicTo(w * .3, h, w * .1, h * .9, w * .1, h * .66)
      ..cubicTo(w * .1, h * .46, w * .3, h * .4, w * .34, h * .2)
      ..cubicTo(w * .42, h * .3, w * .44, h * .36, w * .46, h * .42)
      ..cubicTo(w * .56, h * .3, w * .54, h * .14, w * .5, 0)
      ..close();
    canvas.drawPath(outer, Paint()..color = color);
    final inner = Path()
      ..moveTo(w * .5, h * .5)
      ..cubicTo(w * .62, h * .64, w * .7, h * .74, w * .66, h * .86)
      ..cubicTo(w * .62, h * .96, w * .38, h * .96, w * .34, h * .84)
      ..cubicTo(w * .32, h * .72, w * .44, h * .66, w * .5, h * .5)
      ..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFFFFD27A));
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.color != color;
}

/// A stationery-style primary action: an ink pill with a handwritten label.
class InkButton extends StatelessWidget {
  const InkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.outlined = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand, outlined;

  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    final enabled = onPressed != null;
    final ink = enabled ? palette.ink : palette.ink.withValues(alpha: .3);
    final background = outlined ? Colors.transparent : ink;
    final foreground = outlined ? ink : palette.paper;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: outlined
              ? BorderSide(color: ink.withValues(alpha: .45), width: 1.2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: foreground, size: 20),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: peopleHand(context, size: 24, color: foreground),
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

/// A heading in the handwriting font with an underline stroke.
class PeopleHeading extends StatelessWidget {
  const PeopleHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(text, style: peopleHand(context, size: 26))),
        ?trailing,
      ],
    ),
  );
}
