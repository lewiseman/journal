import 'package:flutter/material.dart';

/// Centers All on initial load, then preserves manual scrolling.
class NoteTagStrip extends StatefulWidget {
  const NoteTagStrip({
    super.key,
    required this.tags,
    required this.selectedTag,
    required this.onSelected,
    this.isLoading = false,
  });

  final List<({String emoji, String name})> tags;
  final String selectedTag;
  final ValueChanged<String> onSelected;
  final bool isLoading;

  @override
  State<NoteTagStrip> createState() => _NoteTagStripState();
}

class _NoteTagStripState extends State<NoteTagStrip> {
  final _scroll = ScrollController();
  final _allTagKey = GlobalKey();
  bool _initialTagCentered = false;
  bool _tagCenterScheduled = false;
  static const _fadeWidth = 48.0;
  final _fade = ValueNotifier<({double left, double right})>((
    left: 0,
    right: 0,
  ));

  @override
  void dispose() {
    _scroll.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _centerInitialTag() {
    if (_initialTagCentered ||
        _tagCenterScheduled ||
        widget.selectedTag != 'All') {
      return;
    }
    _tagCenterScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tagCenterScheduled = false;
      if (!mounted || _initialTagCentered || !_scroll.hasClients) return;
      final target = _allTagKey.currentContext?.findRenderObject();
      if (target == null || !target.attached) return;
      _initialTagCentered = true;
      _scroll.position.ensureVisible(target, alignment: .5);
    });
  }

  void _updateTagFade(ScrollMetrics metrics) {
    final before = (metrics.extentBefore / _fadeWidth).clamp(0.0, 1.0);
    final after = (metrics.extentAfter / _fadeWidth).clamp(0.0, 1.0);
    _fade.value = metrics.axisDirection == AxisDirection.right
        ? (left: before, right: after)
        : (left: after, right: before);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) _centerInitialTag();
    final colors = Theme.of(context).colorScheme;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _updateTagFade(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _initialTagCentered = true;
            }
            _updateTagFade(notification.metrics);
          }
          return false;
        },
        child: ValueListenableBuilder<({double left, double right})>(
          valueListenable: _fade,
          builder: (context, fade, child) => ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final width = bounds.width > 0
                  ? (_fadeWidth / bounds.width).clamp(0.0, .5)
                  : 0.0;
              const ramp = [0.0, .25, .5, .75, 1.0];
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  for (final t in ramp)
                    Colors.black.withValues(
                      alpha:
                          1 - fade.left * (1 - Curves.easeInOut.transform(t)),
                    ),
                  for (final t in ramp.reversed)
                    Colors.black.withValues(
                      alpha:
                          1 - fade.right * (1 - Curves.easeInOut.transform(t)),
                    ),
                ],
                stops: [
                  for (final t in ramp) t * width,
                  for (final t in ramp.reversed) 1 - t * width,
                ],
              ).createShader(bounds);
            },
            child: child,
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(left: 20, top: 4, right: 20, bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tag in widget.tags)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: tag.name == 'All' ? _allTagKey : null,
                      selected: widget.selectedTag == tag.name,
                      showCheckmark: false,
                      avatar: Text(tag.emoji),
                      label: Text(tag.name),
                      labelStyle: TextStyle(
                        color: widget.selectedTag == tag.name
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: widget.selectedTag == tag.name
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      backgroundColor: Colors.transparent,
                      selectedColor: colors.primary,
                      side: BorderSide(
                        color: widget.selectedTag == tag.name
                            ? colors.primary.withValues(alpha: .5)
                            : colors.outlineVariant,
                      ),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      onSelected: (_) {
                        _initialTagCentered = true;
                        widget.onSelected(tag.name);
                      },
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
