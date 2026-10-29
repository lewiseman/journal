import 'package:journal/common.dart';
import 'package:journal/modules/flow/views/widgets/flow_thought_card.dart';

/// Flow's QVAC sheet, drawn like Flow itself: the same paper gradient and
/// thought clouds. Voice opens full-screen capture; Flow AI search opens the
/// question page. Both close the sheet first.
class FlowAssistant extends StatelessWidget {
  const FlowAssistant({
    super.key,
    required this.scrollController,
    required this.onVoice,
    required this.onSearch,
  });
  final ScrollController scrollController;
  final VoidCallback onVoice, onSearch;

  @override
  Widget build(BuildContext context) {
    final paper = NoteColorPreset.paper
        .resolveColors(context.colors)
        .background;
    final narrow =
        MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    void close(VoidCallback then) {
      Navigator.of(context).pop();
      then();
    }

    final voice = _FlowCloudAction(
      key: const ValueKey('flow-assistant-voice'),
      preset: NoteColorPreset.sage,
      alternate: false,
      icon: Icons.mic_none_rounded,
      title: 'Voice',
      caption: 'Say a thought out loud',
      onTap: () => close(onVoice),
    );
    final search = _FlowCloudAction(
      key: const ValueKey('flow-assistant-search'),
      preset: NoteColorPreset.sky,
      alternate: true,
      icon: Icons.manage_search_rounded,
      title: 'Flow AI search',
      caption: 'Ask about your thoughts',
      onTap: () => close(onSearch),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(context.colors.surface, paper, .55)!,
            context.colors.surface,
          ],
        ),
      ),
      child: ListView(
        key: const ValueKey('flow-assistant-actions'),
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            'FLOW',
            style: TextStyle(
              color: context.colors.onSurfaceVariant,
              fontSize: 10,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Speak a thought, or ask about earlier ones.',
            style: TextStyle(
              color: context.colors.onSurfaceVariant,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          if (narrow) ...[
            voice,
            const SizedBox(height: 10),
            search,
          ] else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: voice),
                  const SizedBox(width: 12),
                  Expanded(child: search),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A tappable thought cloud in one of Flow's paper colours.
class _FlowCloudAction extends StatelessWidget {
  const _FlowCloudAction({
    super.key,
    required this.preset,
    required this.alternate,
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });
  final NoteColorPreset preset;
  final bool alternate;
  final IconData icon;
  final String title, caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = preset.resolveColors(context.colors);
    final background = Color.lerp(
      colors.background,
      context.colors.surface,
      .16,
    )!;
    final shape = FlowCloudBorder(
      alternate: alternate,
      side: BorderSide(
        color: colors.foreground.withValues(alpha: context.isDark ? .16 : .12),
      ),
    );
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Semantics(
      button: true,
      label: '$title. $caption',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: background,
        elevation: 4,
        shadowColor: context.colors.shadow.withValues(
          alpha: context.isDark ? .38 : .20,
        ),
        surfaceTintColor: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onTap,
          customBorder: shape,
          splashColor: colors.foreground.withValues(alpha: .06),
          highlightColor: colors.foreground.withValues(alpha: .025),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 150 * scale),
            // Insets keep ink inside the scallops and above the tail, as the
            // thought cards do.
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 26, 28, 26 + shape.tailHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 26, color: colors.foreground),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: TextStyle(
                      color: colors.secondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
