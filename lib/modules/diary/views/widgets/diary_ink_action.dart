import 'package:flutter/services.dart';
import 'package:journal/common.dart';

/// Paper controls still support keyboard activation, focus and screen readers.
class DiaryInkAction extends StatefulWidget {
  const DiaryInkAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
    this.selected,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;
  final bool? selected;
  final String? tooltip;

  @override
  State<DiaryInkAction> createState() => _DiaryInkActionState();
}

class _DiaryInkActionState extends State<DiaryInkAction> {
  bool _pressed = false;
  bool _focused = false;

  void _activate() {
    if (widget.onPressed == null) return;
    HapticFeedback.selectionClick();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    Widget control = Semantics(
      button: true,
      enabled: widget.onPressed != null,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.onPressed == null ? null : _activate,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        mouseCursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onPressed == null
              ? null
              : (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onPressed == null ? null : _activate,
          child: AnimatedScale(
            scale: _pressed ? .96 : 1,
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 110),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: _focused
                    ? Border.all(color: context.colors.primary, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(3),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      control = Tooltip(
        message: widget.tooltip!,
        excludeFromSemantics: true,
        child: control,
      );
    }
    return control;
  }
}
