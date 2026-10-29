import 'dart:math' as math;

import 'package:journal/modules/local_ai/core/ai_router.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/config/diary_typography.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/diary/questions/daily_question_prompt.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_action.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/voice/voice.dart';
import 'package:journal/utils/navigation_helper.dart';
import 'package:journal/utils/time_helper.dart';

enum _DiaryTool { details }

bool _reducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context);

/// The selected reader day is captured when QVAC opens, including empty days.
/// Opening the menu itself never creates a microphone or a conversation.
///
/// The menu is a loose diary page: speaking is the inked centerpiece, and the
/// quieter tools are written on its ruled lines. Every tool needs local AI,
/// so all of them rest until the paired computer is connected.
class DiaryAssistant extends ConsumerStatefulWidget {
  const DiaryAssistant({
    super.key,
    required this.date,
    required this.canAddVoice,
    required this.scrollController,
  });
  final DateTime date;
  final bool canAddVoice;
  final ScrollController scrollController;

  @override
  ConsumerState<DiaryAssistant> createState() => _DiaryAssistantState();
}

class _DiaryAssistantState extends ConsumerState<DiaryAssistant> {
  _DiaryTool? _tool;

  void _open(_DiaryTool? tool) {
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    setState(() {
      _tool = tool;
    });
  }

  void _openVoice() {
    if (!widget.canAddVoice || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    FocusScope.of(context).unfocus();
    context.nav.replace<void, bool>(
      VoiceSessionPage(
        date: widget.date,
        mode: VoiceSessionMode.conversation,
        title: 'Your day, out loud',
      ),
      transition: _reducedMotion(context)
          ? NavTransition.none
          : NavTransition.fade,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_tool) {
      case _DiaryTool.details:
        return DiaryDetailsPage(
          dateString: TimeHelper.dateKey(widget.date),
          scrollController: widget.scrollController,
          onBack: () => _open(null),
        );
      case null:
        break;
    }
    final colors = Theme.of(context).colorScheme;
    final hand = DiaryTypography.of(context).title
        .copyWith(color: colors.onSurface);
    final phase = ref.watch(
      companionControllerProvider.select((state) => state.phase),
    );
    final connected = phase == CompanionPhase.connected;
    final writingReady = ref.watch(
      aiOperationAvailableProvider('suggest-diary-day'),
    );
    final questionReady = ref.watch(
      aiOperationAvailableProvider('ask-diary-question'),
    );
    final day = DiaryRepository.formatDateKey(widget.date);
    final today =
        day ==
        DiaryRepository.formatDateKey(ref.watch(dailyQuestionClockProvider)());
    final speak = connected && widget.canAddVoice;
    return ListView(
      key: const ValueKey('diary-assistant-actions'),
      controller: widget.scrollController,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (!connected && !writingReady) _OfflineNote(phase: phase),
        const SizedBox(height: 12),
        Center(
          child: DiaryInkAction(
            key: const ValueKey('diary-assistant-microphone'),
            label: 'Talk through your day',
            onPressed: speak ? _openVoice : null,
            child: _VoiceInk(enabled: speak),
          ),
        ),
        Text(
          widget.canAddVoice
              ? 'Talk through your day'
              : 'This day is read-only',
          textAlign: TextAlign.center,
          style: hand.copyWith(
            fontSize: 26,
            color: speak
                ? colors.onSurface
                : colors.onSurfaceVariant.withValues(alpha: .5),
          ),
        ),
        const SizedBox(height: 28),
        if (today) _DailyQuestionLine(day: day, connected: questionReady),
        _RuledLine(
          key: const ValueKey('diary-assistant-details'),
          seed: 2,
          enabled: writingReady,
          margin: const _Doodle(_DoodleKind.sparkle, size: 22),
          trailing: const _Doodle(_DoodleKind.arrow, size: 22),
          onTap: writingReady ? () => _open(_DiaryTool.details) : null,
          label: 'Day details',
          child: Text('Day details', style: hand.copyWith(fontSize: 25)),
        ),
      ],
    );
  }
}

/// A single pencilled aside under the date, rather than a status banner.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.phase});
  final CompanionPhase phase;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final note = DiaryTypography.of(context).body.copyWith(
      fontSize: 14,
      height: 1.4,
      fontStyle: FontStyle.italic,
      color: colors.onSurfaceVariant,
    );
    final checking =
        phase == CompanionPhase.loading || phase == CompanionPhase.connecting;
    return Row(
      key: const ValueKey('diary-assistant-offline'),
      children: [
        Flexible(
          child: Text(
            checking
                ? 'Looking for your computer…'
                : 'Local AI isn’t connected',
            style: note,
          ),
        ),
        if (!checking)
          DiaryInkAction(
            key: const ValueKey('diary-assistant-connect'),
            label: 'Connect local AI',
            // The sheet's owner opens local AI settings when it closes with true.
            onPressed: () => Navigator.pop(context, true),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Connect',
                  style: note.copyWith(
                    fontStyle: FontStyle.normal,
                    color: colors.primary,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.wavy,
                    decorationColor: colors.primary.withValues(alpha: .6),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Today's question written on the page, with a small ink control to ask
/// for another. The diary page shows only its text.
class _DailyQuestionLine extends ConsumerWidget {
  const _DailyQuestionLine({required this.day, required this.connected});
  final String day;
  final bool connected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Opted out: nothing AI-related is built or watched.
    if (!ref.watch(dailyQuestionEnabledProvider)) return const SizedBox();
    final colors = Theme.of(context).colorScheme;
    final typography = DiaryTypography.of(context);
    final state = ref.watch(dailyQuestionProvider);
    ref.watch(diaryDaysProvider);
    final summary = ref.watch(noteSummaryProvider);
    final controller = ref.read(dailyQuestionProvider.notifier);
    final view = controller.current(day);
    final asking = DailyQuestionController.asking(summary);
    final occupied = summary.handle != null && !asking;
    final status = !connected || asking
        ? null
        : occupied
        ? 'Another AI task is running.'
        : state.message;
    final ask = connected && !occupied && !asking;
    final tooltip = view == null ? 'Get a question' : 'Another question';
    return _RuledLine(
      key: const ValueKey('diary-assistant-question'),
      seed: 1,
      enabled: connected,
      margin: Text(
        '?',
        textAlign: TextAlign.center,
        style: typography.title.copyWith(
          fontSize: 30,
          height: 1,
          color: colors.primary,
        ),
      ),
      trailing: asking
          ? null
          : DiaryInkAction(
              key: const ValueKey('daily-question-another'),
              label: tooltip,
              tooltip:
                  '$tooltip\n'
                  '${DailyQuestionPrompt.disclosure(controller.selection(day))}',
              onPressed: ask
                  ? () => view == null
                        ? controller.request(day)
                        : controller.regenerate(day, view)
                  : null,
              child: const Center(
                widthFactor: 1,
                child: _Doodle(_DoodleKind.again, size: 24),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (asking)
            const _PencilScribble(key: ValueKey('daily-question-loading'))
          else
            Text(
              view?.question.text ?? 'A question for today',
              key: view == null ? null : const ValueKey('daily-question-text'),
              style: typography.body.copyWith(
                fontSize: 16,
                height: 1.45,
                fontStyle: FontStyle.italic,
                color: view == null
                    ? colors.onSurfaceVariant.withValues(alpha: .7)
                    : colors.onSurface,
              ),
            ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                status,
                key: const ValueKey('daily-question-status'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of the page: a doodle in the margin, writing on a pencilled rule.
class _RuledLine extends StatelessWidget {
  const _RuledLine({
    super.key,
    required this.seed,
    required this.enabled,
    required this.margin,
    required this.child,
    this.trailing,
    this.onTap,
    this.label,
  });
  final int seed;
  final bool enabled;
  final Widget margin, child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? label;

  static const _marginWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    Widget line = CustomPaint(
      painter: _RulePainter(
        seed: seed,
        margin: _marginWidth,
        rule: colors.onSurfaceVariant.withValues(alpha: dark ? .42 : .30),
        marginRule: colors.primary.withValues(alpha: dark ? .38 : .28),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          children: [
            SizedBox(
              width: _marginWidth - 8,
              child: Center(child: margin),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: child,
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    if (onTap != null || label != null) {
      line = DiaryInkAction(label: label ?? '', onPressed: onTap, child: line);
    }
    return AnimatedOpacity(
      opacity: enabled ? 1 : .4,
      duration: _reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: line,
    );
  }
}

class _RulePainter extends CustomPainter {
  const _RulePainter({
    required this.seed,
    required this.margin,
    required this.rule,
    required this.marginRule,
  });
  final int seed;
  final double margin;
  final Color rule, marginRule;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1;
    final random = math.Random(7919 + seed * 104729);
    final y = size.height - 1.5;
    final rule = Path()..moveTo(0, y + random.nextDouble() - .5);
    const steps = 7;
    for (var step = 1; step <= steps; step++) {
      final x = size.width * step / steps;
      rule.quadraticBezierTo(
        x - size.width / steps / 2,
        y + (random.nextDouble() - .5) * 1.8,
        x - random.nextDouble() * (step == steps ? 4 : 0),
        y + (random.nextDouble() - .5) * .8,
      );
    }
    canvas.drawPath(rule, pen..color = this.rule);
    // The margin rule runs through every line, so consecutive lines join up.
    final x = margin + (random.nextDouble() - .5);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x + .6, size.height),
      pen
        ..color = marginRule
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_RulePainter oldDelegate) =>
      seed != oldDelegate.seed ||
      margin != oldDelegate.margin ||
      rule != oldDelegate.rule ||
      marginRule != oldDelegate.marginRule;
}

/// The microphone, inked large inside a pencil ring over a wash of color.
/// When it can listen, sound lines breathe out from either side.
class _VoiceInk extends StatefulWidget {
  const _VoiceInk({required this.enabled});
  final bool enabled;

  @override
  State<_VoiceInk> createState() => _VoiceInkState();
}

class _VoiceInkState extends State<_VoiceInk> with TickerProviderStateMixin {
  late final _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool? _reduced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = _reducedMotion(context);
    if (_reduced == reduced) return;
    final first = _reduced == null;
    _reduced = reduced;
    if (reduced) {
      _draw.value = 1;
    } else if (first) {
      _draw.forward();
    }
    _sync();
  }

  @override
  void didUpdateWidget(_VoiceInk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (widget.enabled && _reduced == false) {
      if (!_breath.isAnimating) _breath.repeat();
    } else {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    return CustomPaint(
      size: const Size(196, 164),
      painter: _VoiceInkPainter(
        draw: _draw,
        breath: _breath,
        animated: _reduced == false && widget.enabled,
        enabled: widget.enabled,
        ink: widget.enabled
            ? colors.onSurface
            : colors.onSurfaceVariant.withValues(alpha: .45),
        ring: colors.onSurfaceVariant.withValues(alpha: dark ? .40 : .30),
        wash: colors.primary.withValues(alpha: dark ? .20 : .12),
        waves: colors.primary,
      ),
    );
  }
}

class _VoiceInkPainter extends CustomPainter {
  _VoiceInkPainter({
    required this.draw,
    required this.breath,
    required this.animated,
    required this.enabled,
    required this.ink,
    required this.ring,
    required this.wash,
    required this.waves,
  }) : super(repaint: Listenable.merge([draw, breath]));

  final Animation<double> draw, breath;
  final bool animated, enabled;
  final Color ink, ring, wash, waves;

  static const _radius = 58.0;
  static const _scale = 2.35;

  // Built once: the wash blob and two loose pencil passes around the mic.
  static final _blob = _wobble(_radius - 4, 2.4, 3, 1);
  static final _rings = [
    _wobble(_radius, .9, 3, 2, sweep: math.pi * 1.9),
    _wobble(_radius + 1.6, 1.2, 4, 5, sweep: math.pi * 1.7, start: 1.4),
  ];

  static Path _wobble(
    double radius,
    double amount,
    int lobes,
    int seed, {
    double sweep = math.pi * 2,
    double start = -.6,
  }) {
    const steps = 48;
    final points = [
      for (var step = 0; step <= steps; step++)
        () {
          final angle = start + step / steps * sweep;
          final r =
              radius +
              math.sin(angle * lobes + seed) * amount +
              math.cos(angle * (lobes + 2) - seed) * amount * .4;
          return Offset(math.cos(angle) * r, math.sin(angle) * r * .97);
        }(),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var step = 1; step < points.length - 1; step++) {
      final middle = Offset.lerp(points[step], points[step + 1], .5)!;
      path.quadraticBezierTo(
        points[step].dx,
        points[step].dy,
        middle.dx,
        middle.dy,
      );
    }
    path.lineTo(points.last.dx, points.last.dy);
    return sweep >= math.pi * 2 ? (path..close()) : path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final reveal = Curves.easeOutCubic.transform(draw.value);
    final t = breath.value;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (enabled) {
      final swell = animated ? 1 + math.sin(t * math.pi * 2) * .025 : 1.0;
      canvas.save();
      canvas.scale(swell * (.85 + .15 * reveal));
      canvas.drawPath(
        _blob,
        Paint()..color = wash.withValues(alpha: wash.a * reveal),
      );
      canvas.restore();
    }
    pen
      ..color = ring
      ..strokeWidth = .9;
    for (final ring in _rings) {
      canvas.drawPath(_trace(ring, reveal), pen);
    }
    if (enabled) {
      // Three pairs of sound lines; each pair swells after the one inside it.
      for (var wave = 0; wave < 3; wave++) {
        final strength = animated
            ? (math.sin((t - wave * .16) * math.pi * 2) * .5 + .5)
            : 1 - wave * .3;
        pen
          ..strokeWidth = 1.6 - wave * .25
          ..color = waves.withValues(
            alpha: (.18 + strength * .62) * reveal * (1 - wave * .18),
          );
        final r = _radius + 12 + wave * 10 + (animated ? strength * 1.5 : 0);
        final reach = .34 - wave * .04;
        for (final side in [0.0, math.pi]) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: r),
            side - reach,
            reach * 2,
            false,
            pen,
          );
        }
      }
    }
    canvas.scale(_scale);
    canvas.translate(-24, -24);
    pen.color = ink;
    for (final (index, path) in diaryVoiceInk.indexed) {
      pen.strokeWidth = (index.isEven ? 2.8 : 2.4) / _scale;
      canvas.drawPath(_trace(path, reveal), pen);
    }
    canvas.restore();
  }

  /// The first [amount] of [path], so the ink appears as if being drawn.
  static Path _trace(Path path, double amount) {
    if (amount >= 1) return path;
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(metric.extractPath(0, metric.length * amount), Offset.zero);
    }
    return out;
  }

  @override
  bool shouldRepaint(_VoiceInkPainter oldDelegate) =>
      animated != oldDelegate.animated ||
      enabled != oldDelegate.enabled ||
      ink != oldDelegate.ink ||
      ring != oldDelegate.ring ||
      wash != oldDelegate.wash ||
      waves != oldDelegate.waves;
}

/// A pencil line writing itself while the computer thinks of a question.
class _PencilScribble extends StatefulWidget {
  const _PencilScribble({super.key});

  @override
  State<_PencilScribble> createState() => _PencilScribbleState();
}

class _PencilScribbleState extends State<_PencilScribble>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reducedMotion(context)) {
      _controller
        ..stop()
        ..value = .6;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Asking for a question',
    child: CustomPaint(
      size: const Size(double.infinity, 24),
      painter: _ScribblePainter(
        progress: _controller,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ScribblePainter extends CustomPainter {
  _ScribblePainter({required this.progress, required this.color})
    : super(repaint: progress);
  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * .8;
    final mid = size.height / 2;
    final path = Path()..moveTo(0, mid);
    // Loops like joined-up handwriting, drawn left to right.
    const loops = 9;
    for (var loop = 0; loop < loops; loop++) {
      final x = width * loop / loops;
      final step = width / loops;
      final rise = 5.5 + math.sin(loop * 1.7) * 2.5;
      path.cubicTo(
        x + step * .55,
        mid - rise * 1.6,
        x + step * .1,
        mid - rise * 1.4,
        x + step * .45,
        mid + 2,
      );
      path.quadraticBezierTo(x + step * .8, mid + 4, x + step, mid);
    }
    final ease = Curves.easeInOut.transform(progress.value);
    final metric = path.computeMetrics().first;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4
      ..color = color.withValues(
        alpha: .7 * (1 - math.max(0, ease - .85) / .15),
      );
    canvas.drawPath(metric.extractPath(0, metric.length * ease), pen);
  }

  @override
  bool shouldRepaint(_ScribblePainter oldDelegate) =>
      color != oldDelegate.color;
}

enum _DoodleKind { sparkle, arrow, again }

/// Tiny pen drawings for the margin and the ends of ruled lines.
class _Doodle extends StatelessWidget {
  const _Doodle(this.kind, {required this.size});
  final _DoodleKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _DoodlePainter(
        kind,
        kind == _DoodleKind.sparkle ? colors.primary : colors.onSurface,
      ),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  const _DoodlePainter(this.kind, this.color);
  final _DoodleKind kind;
  final Color color;

  // Drawn in a 24×24 box.
  static final _sparkle = Path()
    ..moveTo(11, 2.5)
    ..quadraticBezierTo(12.2, 10.6, 20.5, 12.2)
    ..quadraticBezierTo(12.4, 13, 11.4, 21.5)
    ..quadraticBezierTo(10.4, 13.4, 2.5, 12)
    ..quadraticBezierTo(10.3, 10.8, 11, 2.5)
    ..close()
    ..moveTo(19.4, 2.6)
    ..lineTo(19.6, 6.4)
    ..moveTo(17.6, 4.6)
    ..lineTo(21.4, 4.4);
  static final _arrow = Path()
    ..moveTo(3.5, 12.6)
    ..cubicTo(8.6, 11.6, 14.4, 12.4, 20.2, 11.8)
    ..moveTo(15.2, 6.8)
    ..quadraticBezierTo(18.4, 9.6, 20.6, 11.7)
    ..quadraticBezierTo(17.8, 14, 15.6, 17.2);
  static final _again = Path()
    ..addArc(
      Rect.fromCircle(center: const Offset(12, 12.4), radius: 7.4),
      -1.2,
      5.2,
    )
    ..moveTo(14.4, 2.6)
    ..quadraticBezierTo(15.2, 4.4, 15.6, 5.8)
    ..quadraticBezierTo(13.9, 6.6, 12.2, 7.6);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawPath(
      switch (kind) {
        _DoodleKind.sparkle => _sparkle,
        _DoodleKind.arrow => _arrow,
        _DoodleKind.again => _again,
      },
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.5 * 24 / size.width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DoodlePainter oldDelegate) =>
      kind != oldDelegate.kind || color != oldDelegate.color;
}
