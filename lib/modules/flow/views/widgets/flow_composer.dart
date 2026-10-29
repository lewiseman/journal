import 'package:journal/common.dart';

/// Flow's full-width input. Send appears inside it once there is text; voice
/// capture lives in Flow's QVAC sheet.
class FlowComposer extends StatelessWidget {
  const FlowComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Material(
      color: context.colors.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: context.colors.shadow.withValues(alpha: .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(color: context.colors.primary.withValues(alpha: .14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                child: Semantics(
                  label: 'New thought',
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    keyboardAppearance: Theme.of(context).brightness,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
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
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                // Plain swap: the composer sits in a measured scroll view, where
                // a size animation would re-lay itself out mid-layout.
                return AnimatedSwitcher(
                  duration: duration,
                  child: !hasText
                      ? const SizedBox(
                          key: ValueKey(false),
                          width: 12,
                          height: 56,
                        )
                      : Padding(
                          key: const ValueKey(true),
                          padding: const EdgeInsets.all(6),
                          child: IconButton.filled(
                            tooltip: 'Add thought',
                            onPressed: onSend,
                            style: IconButton.styleFrom(
                              fixedSize: const Size(44, 44),
                              minimumSize: const Size(44, 44),
                              backgroundColor: context.colors.primary,
                              foregroundColor: context.colors.onPrimary,
                            ),
                            icon: const Icon(Icons.send_rounded, size: 20),
                          ),
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
