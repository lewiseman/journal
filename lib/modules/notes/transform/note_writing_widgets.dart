import 'package:flutter/material.dart';

import '../views/widgets/note_ai_widgets.dart';

const writingActions = {
  'rewrite-note': 'Rewrite',
  'clarify-note': 'Fix words',
  'expand-note': 'Add detail',
  'tone-note': 'Change tone',
  'markdown-note': 'Organize',
};

const writingTones = {
  'friendly': (
    'Friendly',
    Icons.sentiment_satisfied_alt_rounded,
    'Make the note friendly and warm. Keep its meaning.',
  ),
  'simple': (
    'Simple',
    Icons.lightbulb_outline_rounded,
    'Use simple, everyday words. Keep the meaning and facts.',
  ),
  'formal': (
    'Formal',
    Icons.work_outline_rounded,
    'Make the note polite and professional. Keep its meaning.',
  ),
};

/// A compact route from one decision to one reviewed result.
class NoteWritingSteps extends StatelessWidget {
  const NoteWritingSteps({super.key, required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Choose', 'Preview', 'Use'];
    const icons = [
      Icons.touch_app_outlined,
      Icons.visibility_outlined,
      Icons.check_rounded,
    ];
    final ink = Theme.of(context).colorScheme.primary;
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    return Semantics(
      label: 'Step ${step + 1} of 3: ${labels[step]}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: ink.withValues(alpha: i <= step ? .55 : .12),
                      ),
                    ),
                  Column(
                    children: [
                      Container(
                        width: 42,
                        height: 36,
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: i == step ? .18 : .05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ink.withValues(alpha: i == step ? .6 : .1),
                          ),
                        ),
                        child: Icon(
                          i < step ? Icons.check_rounded : icons[i],
                          size: 21,
                          color: ink.withValues(alpha: i <= step ? 1 : .45),
                        ),
                      ),
                      if (!large) ...[
                        const SizedBox(height: 5),
                        Text(
                          '${i + 1}  ${labels[i]}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontWeight: i == step
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: i == step
                                    ? ink
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
            if (large)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${step + 1}  ${labels[step]}',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: ink),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NoteWritingChoices extends StatelessWidget {
  const NoteWritingChoices({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final single =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final actions = writingActions.keys.toList();
      Widget tile(String action, {bool wide = false}) => _WritingChoice(
        key: ValueKey('writing-action-$action'),
        action: action,
        selected: selected == action,
        horizontal: single || wide,
        onTap: () => onChanged(action),
      );
      return Column(
        children: [
          for (var i = 0; i < actions.length; i += single ? 1 : 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: single || i + 1 == actions.length
                  ? tile(actions[i], wide: true)
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: tile(actions[i])),
                          const SizedBox(width: 8),
                          Expanded(child: tile(actions[i + 1])),
                        ],
                      ),
                    ),
            ),
        ],
      );
    },
  );
}

class _WritingChoice extends StatelessWidget {
  const _WritingChoice({
    super.key,
    required this.action,
    required this.selected,
    required this.horizontal,
    required this.onTap,
  });
  final String action;
  final bool selected, horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.primary;
    final label = Text(
      writingActions[action]!,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
    final art = SizedBox(
      width: 62,
      height: 42,
      child: CustomPaint(
        painter: _WritingPainter(action, ink, noteAiPaper(context)),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: writingActions[action],
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Color.alphaBlend(
          ink.withValues(alpha: selected ? .12 : .025),
          noteAiPaper(context),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: ink.withValues(alpha: selected ? .65 : .18),
            width: selected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: horizontal
                ? Row(
                    children: [
                      art,
                      const SizedBox(width: 12),
                      Expanded(child: label),
                      if (selected)
                        Icon(Icons.check_circle_rounded, size: 19, color: ink),
                    ],
                  )
                : Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: art),
                          const SizedBox(height: 6),
                          label,
                        ],
                      ),
                      if (selected)
                        PositionedDirectional(
                          top: 0,
                          end: 0,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: ink,
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

/// Miniature before/after drawings show what each action does.
class _WritingPainter extends CustomPainter {
  const _WritingPainter(this.action, this.ink, this.paper);
  final String action;
  final Color ink, paper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 80, size.height / 54);
    final pen = Paint()
      ..color = ink
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x, y), Offset(x2, y2), pen);
    void sheet(double x, {bool after = false}) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 6, 27, 40),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        rect.shift(const Offset(2, 2)),
        Paint()..color = ink.withValues(alpha: .1),
      );
      canvas.drawRRect(rect, Paint()..color = paper);
      canvas.drawRRect(rect, pen);
      for (var i = 0; i < (after && action == 'expand-note' ? 5 : 3); i++) {
        final y = 16.0 + i * 5;
        if (after && action == 'markdown-note') {
          canvas.drawCircle(Offset(x + 6, y), 1.1, Paint()..color = ink);
          line(x + 10, y, x + 21, y);
        } else if (!after && action == 'clarify-note') {
          canvas.drawPath(
            Path()
              ..moveTo(x + 5, y)
              ..lineTo(x + 9, y - 2)
              ..lineTo(x + 13, y + 1)
              ..lineTo(x + 21, y - 1),
            pen,
          );
        } else {
          line(x + 5, y, x + (i == 2 ? 17 : 22), y);
        }
      }
    }

    if (action == 'tone-note') {
      final bubble = RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 9, 59, 33),
        const Radius.circular(12),
      );
      canvas.drawRRect(bubble, Paint()..color = ink.withValues(alpha: .08));
      canvas.drawRRect(bubble, pen);
      line(20, 42, 17, 49);
      line(17, 49, 30, 42);
      canvas.drawCircle(const Offset(29, 22), 1.6, Paint()..color = ink);
      canvas.drawCircle(const Offset(49, 22), 1.6, Paint()..color = ink);
      canvas.drawArc(const Rect.fromLTWH(29, 21, 20, 13), .2, 2.7, false, pen);
    } else {
      sheet(2);
      sheet(49, after: true);
      line(33, 26, 44, 26);
      line(40, 22, 44, 26);
      line(40, 30, 44, 26);
      if (action == 'rewrite-note') {
        canvas.drawPath(
          Path()
            ..moveTo(59, 42)
            ..lineTo(69, 29)
            ..lineTo(73, 32)
            ..lineTo(63, 45)
            ..close(),
          Paint()..color = ink,
        );
      } else if (action == 'clarify-note') {
        line(61, 37, 65, 41);
        line(65, 41, 73, 33);
      } else if (action == 'expand-note') {
        line(70, 39, 78, 39);
        line(74, 35, 74, 43);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WritingPainter oldDelegate) =>
      oldDelegate.action != action ||
      oldDelegate.ink != ink ||
      oldDelegate.paper != paper;
}
