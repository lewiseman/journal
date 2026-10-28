import 'dart:math' as math;

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/flow/views/widgets/flow_composer.dart';
import 'package:journal/modules/flow/views/widgets/flow_opening.dart';
import 'package:journal/modules/flow/views/widgets/flow_thought_card.dart';

class FlowPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FlowPage> createState() => _FlowPageState();
}

class _FlowPageState extends ConsumerState<FlowPage> {
  final _scroll = ScrollController();
  final _draft = TextEditingController();
  final _focus = FocusNode();
  final _composerKey = GlobalKey();
  double _composerHeight = 56;
  bool _measurementScheduled = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _measureComposer();
  }

  void _focusChanged() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _focus.unfocus();
  }

  void _measureComposer() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final box = _composerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          box.hasSize &&
          (box.size.height - _composerHeight).abs() > .5) {
        setState(() => _composerHeight = box.size.height);
      }
    });
  }

  void _send() {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    try {
      ref.read(thoughtsRepositoryProvider).saveThought(content: text);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Couldn’t save your thought. Your draft is still here.',
          ),
          action: SnackBarAction(label: 'Retry', onPressed: _send),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _draft.clear();
    _focus.unfocus();
    if (_scroll.hasClients) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _openThought(ThoughtEntity thought) {
    _focus.unfocus();
    final paper = flowThoughtColors(thought, context.colors);
    _showSheet(
      color: paper.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR THOUGHT',
            style: TextStyle(
              color: paper.secondary,
              fontSize: 10,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            DateFormat('EEEE, MMMM d · h:mm a').format(thought.createdAt),
            style: TextStyle(color: paper.secondary, fontSize: 12),
          ),
          const SizedBox(height: 24),
          SelectableText(
            thought.content,
            style: TextStyle(
              fontSize: 23,
              height: 1.5,
              letterSpacing: -.4,
              color: paper.foreground,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _openVoice() {
    _focus.unfocus();
    if (ModalRoute.of(context)?.isCurrent == false) return;
    context.nav.push<void>(
      const VoiceSessionPage(
        mode: VoiceSessionMode.transcription,
        title: 'Capture a thought',
        target: 'flow',
      ),
      transition:
          MediaQuery.disableAnimationsOf(context) ||
              MediaQuery.accessibleNavigationOf(context)
          ? NavTransition.none
          : NavTransition.fade,
    );
  }

  void _showSheet({required Widget child, Color? color}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: color ?? context.colors.surface,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thoughts = ref.watch(thoughtsStreamProvider);
    final saved = thoughts.asData?.value ?? const <ThoughtEntity>[];
    final reduced = MediaQuery.disableAnimationsOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final tabActive = TickerMode.valuesOf(context).enabled;
    final paper = NoteColorPreset.paper
        .resolveColors(context.colors)
        .background;
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
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = FlowSceneLayout(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  textScale: MediaQuery.textScalerOf(context).scale(16) / 16,
                  composerHeight: _composerHeight,
                  thoughtCount: saved.length,
                );
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    _history(layout, reduced, saved, thoughts),
                    AnimatedBuilder(
                      animation: _scroll,
                      builder: (context, _) => _floatingScene(
                        layout,
                        reduced: reduced,
                        keyboard: keyboard,
                        tabActive: tabActive,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _history(
    FlowSceneLayout layout,
    bool reduced,
    List<ThoughtEntity> thoughts,
    AsyncValue<List<ThoughtEntity>> state,
  ) => CustomScrollView(
    key: const PageStorageKey('flow-history'),
    controller: _scroll,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    slivers: [
      SliverPersistentHeader(
        delegate: FlowOpening(
          layout: layout,
          thoughts: thoughts.take(layout.previewCount).toList(),
          onOpen: _openThought,
          reduced: reduced,
          status: state.when(
            data: (_) => const Text(
              'A little space for what’s on your mind.\nWrite your first thought below.',
              textAlign: TextAlign.center,
            ),
            loading: () => const Text(
              'Loading your thoughts…',
              textAlign: TextAlign.center,
            ),
            error: (_, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Couldn’t load your thoughts.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => ref.invalidate(thoughtsStreamProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: FlowSceneLayout.gutter),
        sliver: SliverMasonryGrid.count(
          crossAxisCount: layout.columns,
          mainAxisSpacing: FlowSceneLayout.gap,
          crossAxisSpacing: FlowSceneLayout.gap,
          childCount: thoughts.length - layout.previewCount,
          itemBuilder: (context, index) {
            final thought = thoughts[index + layout.previewCount];
            return SizedBox(
              height:
                  [184.0, 150.0, 172.0, 206.0][index % 4] * layout.cardScale,
              child: FlowThoughtCard(
                key: ValueKey('flow-thought-${thought.uuid}'),
                thought: thought,
                onTap: () => _openThought(thought),
              ),
            );
          },
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Text(
            'Every little thought has a place.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _floatingScene(
    FlowSceneLayout layout, {
    required bool reduced,
    required bool keyboard,
    required bool tabActive,
  }) {
    final offset = _scroll.hasClients ? math.max(0.0, _scroll.offset) : 0.0;
    final progress = layout.progress(offset, reduced: reduced);
    final overlap = layout.composerOverlap(offset, progress);
    final visibility = _focus.hasFocus
        ? 1.0
        : (1 - overlap / math.max(80, _composerHeight * .7)).clamp(0.0, 1.0);
    final mascotVisibility = keyboard
        ? 0.0
        : (1 - progress * 2).clamp(0.0, 1.0);
    final mascotSpace = math.max(
      0.0,
      layout.composerTop - layout.previewBottom - 22,
    );
    return Stack(
      children: [
        Positioned(
          top: layout.previewBottom + 8 - offset * .12,
          height: mascotSpace,
          left: 24,
          right: 24,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: mascotVisibility,
                child: _FlowMascot(
                  playing: tabActive && !reduced && mascotVisibility > .01,
                  showCaption: mascotSpace > 175 && layout.textScale < 1.5,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: FlowSceneLayout.bottom,
          child: Transform.translate(
            offset: Offset(
              0,
              _focus.hasFocus ? 0 : -math.min(overlap * .45, 64.0),
            ),
            child: IgnorePointer(
              ignoring: visibility < .05 || !tabActive,
              child: ExcludeSemantics(
                excluding: visibility < .05 || !tabActive,
                child: ExcludeFocus(
                  excluding: visibility < .05 || !tabActive,
                  child: Opacity(
                    opacity: visibility,
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 600,
                          maxHeight: math.max(
                            0,
                            layout.height - FlowSceneLayout.bottom - 12,
                          ),
                        ),
                        child:
                            NotificationListener<SizeChangedLayoutNotification>(
                              onNotification: (_) {
                                _measureComposer();
                                return true;
                              },
                              child: SizeChangedLayoutNotifier(
                                child: SingleChildScrollView(
                                  key: _composerKey,
                                  primary: false,
                                  reverse: true,
                                  child: FlowComposer(
                                    controller: _draft,
                                    focusNode: _focus,
                                    onSend: _send,
                                    onVoice: _openVoice,
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowMascot extends StatelessWidget {
  const _FlowMascot({required this.playing, required this.showCaption});

  final bool playing;
  final bool showCaption;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 186),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 170,
                  maxHeight: 156,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        context.colors.primary.withValues(alpha: .065),
                        context.colors.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                  child: TransparentVideoPlayer(
                    assetPath: 'assets/videos/reflecting.mp4',
                    stackedAlpha: true,
                    playing: playing,
                    placeholder: Image.asset(
                      'assets/images/j.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showCaption) ...[
            const SizedBox(height: 4),
            Text(
              'A passing thought counts, too.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}
