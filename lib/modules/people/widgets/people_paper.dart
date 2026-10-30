import 'dart:math';

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';

/// App surfaces and accents, with warm paper reserved for the notes themselves.
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

  static PeoplePalette of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final paper = context.isDark
        ? const Color(0xFF2A241F)
        : const Color(0xFFFCF7EE);
    return PeoplePalette._(
      desk: theme.scaffoldBackgroundColor,
      paper: paper,
      ink: colors.onSurface,
      muted: colors.onSurfaceVariant,
      clay: colors.primary,
      wax: colors.error,
      rule: colors.outlineVariant,
    );
  }

  final Color desk, paper, ink, muted, clay, wax, rule;

  static const charColor = Color(0xFF1E140E);
  static const scorchColor = Color(0xFF7A4A1E);
}

TextStyle peopleTitle(BuildContext context, {double size = 30, Color? color}) =>
    Theme.of(context).textTheme.titleLarge!.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: color ?? PeoplePalette.of(context).ink,
    );

TextStyle peopleBody(BuildContext context, {double? size, Color? color}) =>
    Theme.of(context).textTheme.bodyLarge!.copyWith(
      fontSize: size,
      color: color ?? PeoplePalette.of(context).ink,
    );

/// Shared app background, typography and a width-limited scrolling body.
class PeopleScaffold extends StatelessWidget {
  const PeopleScaffold({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 40),
    this.actions,
  });
  final String title;
  final List<Widget> children;
  final EdgeInsets padding;
  final List<Widget>? actions;

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
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: actions,
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(padding: padding, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// Coordinated tab scrolling keeps the tabs visible as the title collapses.
class PeopleTabbedScaffold extends StatelessWidget {
  const PeopleTabbedScaffold({
    super.key,
    required this.title,
    required this.tabs,
    required this.views,
    this.actions,
    this.headerArtwork,
  });

  final String title;
  final List<Widget> tabs, views;
  final List<Widget>? actions;
  final Widget? headerArtwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artwork = headerArtwork;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final compactHeader = MediaQuery.sizeOf(context).height < 500;
    final tabHeight = artwork == null ? kTextTabBarHeight : 76.0;
    final expandedHeight = artwork == null
        ? null
        : compactHeader
        ? 224.0
        : 280.0;
    return DefaultTabController(
      length: tabs.length,
      child: QvacAssistantPage(
        enabled: false,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverOverlapAbsorber(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
                sliver: artwork == null
                    ? SliverAppBar.large(
                        backgroundColor: theme.scaffoldBackgroundColor,
                        surfaceTintColor: Colors.transparent,
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        actions: actions,
                        bottom: TabBar(
                          tabs: tabs,
                          labelStyle: theme.textTheme.labelLarge,
                          unselectedLabelStyle: theme.textTheme.labelLarge,
                          dividerColor: theme.colorScheme.outlineVariant,
                        ),
                      )
                    : SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final expansion =
                              1 -
                              (constraints.scrollOffset /
                                      (expandedHeight! -
                                          kToolbarHeight -
                                          tabHeight))
                                  .clamp(0.0, 1.0);
                          final inset = max(
                            20.0,
                            (constraints.crossAxisExtent - 640) / 2,
                          );
                          final canPop = Navigator.of(context).canPop();
                          return SliverAppBar(
                            pinned: true,
                            expandedHeight: expandedHeight,
                            backgroundColor: theme.scaffoldBackgroundColor,
                            surfaceTintColor: Colors.transparent,
                            scrolledUnderElevation: 0,
                            actions: actions,
                            flexibleSpace: FlexibleSpaceBar(
                              expandedTitleScale: textScale > 1.4 ? 1.15 : 1.6,
                              centerTitle: false,
                              titlePadding: EdgeInsetsDirectional.only(
                                start:
                                    inset + (canPop ? 52 : 0) * (1 - expansion),
                                bottom:
                                    tabHeight +
                                    4 +
                                    (compactHeader ? 20 : 40) * expansion,
                              ),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -.35,
                                ),
                              ),
                              background: SafeArea(
                                bottom: false,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: compactHeader ? 48 : 64,
                                      right: inset,
                                      width: min(
                                        compactHeader ? 104.0 : 164.0,
                                        (constraints.crossAxisExtent -
                                                inset * 2) *
                                            .44,
                                      ),
                                      height: compactHeader ? 104 : 164,
                                      child: artwork,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            bottom: PreferredSize(
                              preferredSize: Size.fromHeight(tabHeight),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  inset,
                                  4,
                                  inset,
                                  16,
                                ),
                                child: Container(
                                  height: 56,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color:
                                        theme.colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant
                                          .withValues(alpha: .45),
                                    ),
                                  ),
                                  child: TabBar(
                                    tabs: tabs,
                                    dividerHeight: 0,
                                    indicatorSize: TabBarIndicatorSize.tab,
                                    indicatorAnimation:
                                        TabIndicatorAnimation.linear,
                                    indicator: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(17),
                                      border: Border.all(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: .12),
                                      ),
                                    ),
                                    labelPadding: EdgeInsets.symmetric(
                                      horizontal: textScale > 1.4 ? 4 : 10,
                                    ),
                                    labelStyle: theme.textTheme.labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    unselectedLabelStyle:
                                        theme.textTheme.labelLarge,
                                    labelColor:
                                        theme.colorScheme.onPrimaryContainer,
                                    unselectedLabelColor:
                                        theme.colorScheme.onSurfaceVariant,
                                    splashBorderRadius: BorderRadius.circular(
                                      17,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
            body: TabBarView(children: views),
          ),
        ),
      ),
    );
  }
}

class PeopleTabView extends StatelessWidget {
  const PeopleTabView({super.key, required this.slivers});
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: Builder(
      builder: (context) => CustomScrollView(
        key: PageStorageKey(key),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverPadding(
              padding: EdgeInsets.fromLTRB(
                max(20, (constraints.crossAxisExtent - 640) / 2),
                20,
                max(20, (constraints.crossAxisExtent - 640) / 2),
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverMainAxisGroup(slivers: slivers),
            ),
          ),
        ],
      ),
    ),
  );
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

/// A primary action using the app's colors and button typography.
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
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    return outlined
        ? OutlinedButton(onPressed: onPressed, style: style, child: child)
        : FilledButton(onPressed: onPressed, style: style, child: child);
  }
}

/// A compact section heading in the app's selected font.
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
        Expanded(child: Text(text, style: peopleTitle(context, size: 18))),
        ?trailing,
      ],
    ),
  );
}
