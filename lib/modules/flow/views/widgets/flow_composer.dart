import 'package:journal/common.dart';

class FlowComposer extends StatelessWidget {
  const FlowComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Material(
            color: context.colors.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            elevation: 8,
            shadowColor: context.colors.shadow.withValues(alpha: .12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
              side: BorderSide(
                color: context.colors.primary.withValues(alpha: .14),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Semantics(
                  label: 'New thought',
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    keyboardAppearance: Theme.of(context).brightness,
                    textCapitalization: TextCapitalization.sentences,
                    scrollPadding: EdgeInsets.zero,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      color: context.colors.onSurface,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'What’s on your mind?',
                      hintStyle: TextStyle(
                        color: context.colors.onSurfaceVariant.withValues(
                          alpha: .7,
                        ),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            return AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasText
                    ? context.colors.primary
                    : context.colors.primaryContainer,
                boxShadow: [
                  BoxShadow(
                    color: context.colors.primary.withValues(alpha: .12),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: IconButton(
                  tooltip: hasText ? 'Add thought' : 'Voice capture',
                  onPressed: hasText ? onSend : onVoice,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(56, 56),
                    shape: const CircleBorder(),
                    foregroundColor: hasText
                        ? context.colors.onPrimary
                        : context.colors.onPrimaryContainer,
                  ),
                  icon: SizedBox.square(
                    dimension: 24,
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: .65,
                            end: 1,
                          ).animate(animation),
                          child: RotationTransition(
                            turns: Tween<double>(
                              begin: -.125,
                              end: 0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                      ),
                      child: Icon(
                        hasText ? Icons.send_rounded : Icons.mic_none_rounded,
                        key: ValueKey(hasText),
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
