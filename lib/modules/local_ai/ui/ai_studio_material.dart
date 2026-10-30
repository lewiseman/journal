import 'package:flutter/material.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';

TextStyle studioTitle(BuildContext context, {double size = 25}) => TextStyle(
  fontFamily: 'Lora',
  fontSize: size,
  color: Theme.of(context).colorScheme.onSurface,
  height: 1.25,
  letterSpacing: -.6,
);

/// The same irregular paper and fibers used by the diary, on a quiet desk.
class AiStudioPaper extends StatelessWidget {
  const AiStudioPaper({
    super.key,
    required this.child,
    this.seed = 51,
    this.padding = const EdgeInsets.all(22),
    this.color,
    this.onTap,
    this.onHighlightChanged,
  });

  final Widget child;
  final int seed;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHighlightChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final shape = DiaryPaperShape(seed: seed, cornerRadius: 8);
    return CustomPaint(
      painter: DiaryPaperPainter(
        shape: shape,
        paper:
            color ?? (dark ? const Color(0xff28252f) : const Color(0xfffff9ee)),
        ink: colors.onSurface,
        shadow: true,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onHighlightChanged: onHighlightChanged,
          borderRadius: BorderRadius.circular(8),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class AiStudioRule extends StatelessWidget {
  const AiStudioRule({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: .55),
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
              label!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Caveat',
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: Theme.of(context).colorScheme.outlineVariant
                  .withValues(alpha: .55),
            ),
          ),
        ],
      ],
    ),
  );
}
