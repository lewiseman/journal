import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

/// Search chrome shares the diary's cached, theme-aware paper material.
class DiarySearchPaper extends StatelessWidget {
  const DiarySearchPaper({
    super.key,
    required this.child,
    this.color,
    this.variant = 0,
    this.onTap,
    this.padding = const EdgeInsets.all(22),
  });

  final Widget child;
  final Color? color;
  final int variant;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return CustomPaint(
      painter: DiaryPaperStamp(
        paper: color ?? context.colors.surfaceContainerLowest,
        ink: context.colors.onSurface,
        shadowColor: context.colors.shadow,
        edgeScale: .34,
        variant: variant,
      ),
      child: onTap == null
          ? content
          : Semantics(
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onTap,
                  child: content,
                ),
              ),
            ),
    );
  }
}
