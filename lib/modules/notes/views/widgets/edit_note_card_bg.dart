import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:journal/common.dart';

import 'note_paper_surface.dart';

export 'note_paper_surface.dart' show NotePaperSurface;

/// Lets the page restore the folded preview without replacing the scroll view.
class EditNoteCardController extends ChangeNotifier {
  void collapse() => notifyListeners();
}

/// Scrolling unfolds the paper without leaving preview. Only an explicit edit
/// action calls [onEdit], after the corner has covered its icon.
class EditNoteCardBg extends StatefulWidget {
  const EditNoteCardBg({
    super.key,
    required this.color,
    required this.children,
    required this.isPreviewMode,
    required this.onEdit,
    this.readOnly = false,
    this.onExpansionChanged,
    this.controller,
    this.paperOpacity = const AlwaysStoppedAnimation<double>(.8),
    this.maxWidth = 720,
    this.maxHeight = 820,
  }) : assert(maxWidth > 0),
       assert(maxHeight > 0);

  final Color color;
  final List<Widget> children;
  final bool isPreviewMode;
  final bool readOnly;
  final VoidCallback onEdit;
  final EditNoteCardController? controller;

  /// Fades only the paper fill, leaving content, the edit icon, and curl opaque.
  final Animation<double> paperOpacity;

  /// Size limits for the folded preview. Immersive paper fills its viewport.
  final double maxWidth;
  final double maxHeight;

  /// Zero is the folded card; one is flat paper filling the entire viewport.
  final ValueChanged<double>? onExpansionChanged;

  @override
  State<EditNoteCardBg> createState() => _EditNoteCardBgState();
}

class _EditNoteCardBgState extends State<EditNoteCardBg>
    with SingleTickerProviderStateMixin {
  static const _transitionDistance = 100.0;
  static const _bottomFadeHeight = 110.0;
  static const _unfoldDuration = Duration(milliseconds: 320);
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 30,
  );

  late final _expansion = AnimationController(
    vsync: this,
    value: widget.isPreviewMode ? 0 : 1,
    duration: _unfoldDuration,
  )..addListener(_publishExpansion);
  late final _scroll = _PaperScrollController(this);
  final _bottomFade = ValueNotifier<double>(0);
  bool _reduceMotion = false;
  bool _enteringEdit = false;
  bool _collapsing = false;
  bool _dragCanExpand = false;
  bool _dragChangedExpansion = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_collapse);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant EditNoteCardBg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_collapse);
      widget.controller?.addListener(_collapse);
    }
    if (oldWidget.isPreviewMode && !widget.isPreviewMode) {
      _dragCanExpand = false;
      _dragChangedExpansion = false;
      _animateTo(1).onError<TickerCanceled>((_, _) {});
    }
  }

  void _publishExpansion() {
    widget.onExpansionChanged?.call(_expansion.value);
  }

  void _updateBottomFade(ScrollMetrics metrics) {
    _bottomFade.value = (metrics.extentAfter / _bottomFadeHeight).clamp(
      0.0,
      1.0,
    );
  }

  Future<void> _animateTo(double target) async {
    if (_reduceMotion || _expansion.value == target) {
      if (_expansion.value != target) {
        // didUpdateWidget may be running in a listening ancestor's build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _expansion.value = target;
        });
      }
      return;
    }
    await _expansion.animateTo(target, curve: Curves.easeOutCubic).orCancel;
  }

  Future<void> _edit() async {
    if (widget.readOnly ||
        _enteringEdit ||
        _collapsing ||
        !widget.isPreviewMode) {
      return;
    }
    setState(() => _enteringEdit = true);
    try {
      if (_reduceMotion) {
        _expansion.value = 1;
      } else {
        await _animateTo(1);
      }
      if (mounted && _enteringEdit && !widget.readOnly) widget.onEdit();
    } on TickerCanceled {
      // Leaving the route cancels the unfold animation.
    } finally {
      if (mounted) setState(() => _enteringEdit = false);
    }
  }

  Future<void> _collapse() async {
    if (_collapsing) return;
    setState(() {
      _collapsing = true;
      _enteringEdit = false;
    });
    _dragCanExpand = false;
    _dragChangedExpansion = false;
    if (_scroll.hasClients) {
      // Explicit Back can restore the preview from anywhere in a long note.
      // Returning to the top also lets the next upward pull unfold it again.
      _scroll.jumpTo(_scroll.position.minScrollExtent);
    }
    try {
      await _animateTo(0);
    } on TickerCanceled {
      // The route may be removed while the paper is folding.
    } finally {
      if (mounted) setState(() => _collapsing = false);
    }
  }

  void _beginDrag(ScrollMetrics metrics) {
    _dragCanExpand = false;
    _dragChangedExpansion = false;
    if (widget.readOnly ||
        _enteringEdit ||
        _collapsing ||
        !widget.isPreviewMode) {
      return;
    }
    _expansion.stop();
    // Freeze eligibility: the larger viewport can make a previously long note
    // fit without scrolling while the user is still unfolding it.
    _dragCanExpand =
        widget.isPreviewMode &&
        (_expansion.value > 0 ||
            metrics.maxScrollExtent - metrics.minScrollExtent > .5);
    _dragChangedExpansion = _expansion.value > 0 && _expansion.value < 1;
  }

  double _consumeExpansion(double delta) {
    if (!_dragCanExpand || _enteringEdit || _collapsing) return delta;
    final before = _expansion.value;
    final after = (before - delta / _transitionDistance).clamp(0.0, 1.0);
    if (before == after) return delta;
    _dragChangedExpansion = true;
    _expansion.value = after;
    return delta + (after - before) * _transitionDistance;
  }

  bool _settleExpansion() {
    if (!_dragChangedExpansion || !widget.isPreviewMode || _enteringEdit) {
      return false;
    }
    _dragChangedExpansion = false;
    final value = _expansion.value;
    if (value == 0 || value == 1) return false;
    final target = value < .5 ? 0.0 : 1.0;
    if (_reduceMotion) {
      _expansion.value = target;
    } else {
      // Distance chooses the destination; fling velocity cannot bypass it.
      _expansion.animateWith(ScrollSpringSimulation(_spring, value, target, 0));
    }
    return true;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_collapse);
    _scroll.dispose();
    _bottomFade.dispose();
    _expansion.dispose();
    super.dispose();
  }

  Widget _fadeScrollableContent(double folded, {required Widget child}) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            _updateBottomFade(notification.metrics);
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) {
              _updateBottomFade(notification.metrics);
            }
            return false;
          },
          child: ValueListenableBuilder<double>(
            valueListenable: _bottomFade,
            builder: (context, fade, child) => ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) =>
                  LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Colors.white.withValues(
                        alpha: 1 - (widget.isPreviewMode ? folded * fade : 0),
                      ),
                    ],
                  ).createShader(
                    Rect.fromLTRB(
                      bounds.left,
                      math.max(bounds.top, bounds.bottom - _bottomFadeHeight),
                      bounds.right,
                      bounds.bottom,
                    ),
                  ),
              // Keep the scroll view mounted while unfolding.
              // Only content fades; the paper and curl stay crisp.
              child: child,
            ),
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _expansion,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final folded = 1 - _expansion.value;
        final previewWidth = math.min(
          widget.maxWidth * .94,
          math.max(0.0, constraints.maxWidth - 52),
        );
        final previewHeight = math.min(
          math.min(MediaQuery.sizeOf(context).height * .75, widget.maxHeight),
          math.max(0.0, constraints.maxHeight - 52),
        );
        // Only the preview is constrained. At full expansion there is no outer
        // gutter, height cap, corner radius, or shadow, including on tablets.
        final width =
            previewWidth +
            (constraints.maxWidth - previewWidth) * _expansion.value;
        final height =
            previewHeight +
            (constraints.maxHeight - previewHeight) * _expansion.value;
        final fold =
            math.min(width * .4, (width * .23).clamp(72.0, 104.0)) * folded;
        final shape = NotePaperShape(fold: fold, radius: 26 * folded);
        return Align(
          // alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                if (!widget.readOnly && widget.isPreviewMode && folded > 0)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Opacity(
                          opacity: ((folded - .35) / .65).clamp(0.0, 1.0),
                          child: SizedBox.square(
                            dimension: 48,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.edit_outlined,
                                  size: 22,
                                  color: context.colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                CustomPaint(
                  key: const ValueKey('note-paper-content'),
                  painter: NotePaperShadowPainter(shape, folded),
                  child: ClipPath(
                    clipper: shape,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FadeTransition(
                          opacity: widget.paperOpacity,
                          child: NotePaperSurface(color: widget.color),
                        ),
                        IgnorePointer(
                          ignoring: _enteringEdit || _collapsing,
                          child: _fadeScrollableContent(
                            folded,
                            child: CustomScrollView(
                              controller: _scroll,
                              // An expanded note may fit after its margins vanish;
                              // it must still accept a pull to restore the fold.
                              physics: const AlwaysScrollableScrollPhysics(),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              slivers: [
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    24,
                                    24,
                                    24,
                                    24 +
                                        fold +
                                        MediaQuery.paddingOf(context).bottom,
                                  ),
                                  sliver: SliverMainAxisGroup(
                                    slivers: widget.children,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: NotePaperCurlPainter(shape, widget.color, folded),
                  ),
                ),
                // The icon is painted under the curl, but its full 48px target
                // sits above it so the paper cannot intercept part of a tap.
                if (!widget.readOnly &&
                    widget.isPreviewMode &&
                    folded >= .7 &&
                    !_enteringEdit &&
                    !_collapsing)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: 'Edit note',
                      onPressed: _edit,
                      style: IconButton.styleFrom(
                        fixedSize: const Size(48, 48),
                      ),
                      icon: const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _PaperScrollController extends ScrollController {
  _PaperScrollController(this.paper);

  final _EditNoteCardBgState paper;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _PaperScrollPosition(
    paper: paper,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

/// Drag distance owns the transition, rather than a fake leading sliver. Native
/// ballistics cannot change the curl when a fling reaches the content's top.
class _PaperScrollPosition extends ScrollPositionWithSingleContext {
  _PaperScrollPosition({
    required this.paper,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _EditNoteCardBgState paper;

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    paper._beginDrag(this);
    return super.drag(details, dragCancelCallback);
  }

  @override
  void applyUserOffset(double delta) {
    updateUserScrollDirection(
      delta > 0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    // Read earlier text before a downward drag is allowed to restore the fold.
    if (delta > 0 && pixels > minScrollExtent) {
      final contentDelta = math.min(delta, pixels - minScrollExtent);
      super.applyUserOffset(contentDelta);
      delta -= contentDelta;
    }
    if (pixels <= minScrollExtent + .5 && !outOfRange) {
      delta = paper._consumeExpansion(delta);
    }
    if (delta.abs() > .0001) super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    if (paper._settleExpansion()) {
      goIdle();
      return;
    }
    super.goBallistic(velocity);
  }

  @override
  void pointerScroll(double delta) {
    if (delta == 0) return;
    paper._beginDrag(this);
    goIdle();
    applyUserOffset(-delta);
    goBallistic(0);
  }
}
