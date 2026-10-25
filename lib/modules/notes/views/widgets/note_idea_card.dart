import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';

/// A small idea ticket that can become the first line of a new note.
class NoteIdeaCard extends StatefulWidget {
  const NoteIdeaCard({super.key, required this.onUsePrompt});

  final ValueChanged<String> onUsePrompt;

  @override
  State<NoteIdeaCard> createState() => _NoteIdeaCardState();
}

class _NoteIdeaCardState extends State<NoteIdeaCard> {
  static const _prompts = [
    'A tiny idea worth trying.',
    'Three places I want to go.',
    'Something I want to learn.',
    'A recipe for a slower morning.',
    'A project for a rainy day.',
  ];

  final _random = math.Random();
  int _promptIndex = 0;

  void _shuffle() {
    setState(() {
      _promptIndex =
          (_promptIndex + 1 + _random.nextInt(_prompts.length - 1)) %
          _prompts.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final prompt = _prompts[_promptIndex];

    return Stack(
      children: [
        Positioned(
          top: 20,
          left: 12,
          right: 12,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 6,
          right: 6,
          bottom: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  context.colors.primaryContainer,
                  context.colors.surfaceContainerHigh,
                ],
              ),
              border: Border.all(
                color: context.colors.primary.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Idea shuffle',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: context.colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Another idea',
                        onPressed: _shuffle,
                        icon: Icon(
                          Icons.shuffle_rounded,
                          size: 18,
                          color: context.colors.primary,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Semantics(
                    liveRegion: true,
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.topLeft,
                        children: [...previousChildren, ?currentChild],
                      ),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.06),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        prompt,
                        key: ValueKey(_promptIndex),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: context.colors.onPrimaryContainer,
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.4,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExcludeSemantics(
                    child: SizedBox(
                      width: double.infinity,
                      height: 1,
                      child: CustomPaint(
                        painter: _TicketPerforationPainter(context.colors),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => widget.onUsePrompt(prompt),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        foregroundColor: context.colors.onPrimary,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(child: Text('Write this')),
                          SizedBox(width: 7),
                          Icon(Icons.arrow_outward_rounded, size: 15),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TicketPerforationPainter extends CustomPainter {
  const _TicketPerforationPainter(this.colors);
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.primary.withValues(alpha: 0.35)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + 2, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TicketPerforationPainter oldDelegate) =>
      colors != oldDelegate.colors;
}
