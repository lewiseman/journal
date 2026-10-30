import '../local_ai/core/ai_router.dart';
import '../local_ai/core/ai_settings.dart';

import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';

import 'qvac_assistant_scope.dart';

const qvacArtwork = 'assets/images/more_local_qvac.png';

/// Lives above the Navigator, with only the assistant layer listening to motion
/// and presentation changes. The app underneath is retained as a static child.
class QvacAssistantHost extends StatelessWidget {
  const QvacAssistantHost({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
  });
  final QvacAssistantController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => QvacAssistantScope(
    controller: controller,
    child: Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: _FloatingAssistant(
              controller: controller,
              navigatorKey: navigatorKey,
            ),
          ),
        ),
      ],
    ),
  );
}

class _FloatingAssistant extends StatefulWidget {
  const _FloatingAssistant({
    required this.controller,
    required this.navigatorKey,
  });
  final QvacAssistantController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  @override
  State<_FloatingAssistant> createState() => _FloatingAssistantState();
}

class _FloatingAssistantState extends State<_FloatingAssistant>
    with SingleTickerProviderStateMixin {
  static const _diameter = 68.0;
  final _layer = GlobalKey();
  final _floatingLink = LayerLink();
  late final _motion = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: const Duration(milliseconds: 440),
    value: 1,
  );
  Rect? _from, _to;
  double _fromDock = 0, _toDock = 0;
  Offset _resting = const Offset(1, 1);
  Size _size = Size.zero;
  Rect _safe = Rect.zero;
  bool _dragging = false, _overDismiss = false, _closing = false;
  bool _reduced = false, _sheetOpen = false;
  Offset _grabOffset = Offset.zero;

  double get _progress =>
      Curves.easeInOutCubicEmphasized.transform(_motion.value);
  Rect? get _rect => _to == null ? null : Rect.lerp(_from, _to, _progress);
  double get _dock => lerpDouble(_fromDock, _toDock, _progress)!;
  Rect get _floating => Rect.fromLTWH(
    _safe.left + _resting.dx * math.max(0, _safe.width - _diameter),
    _safe.top + _resting.dy * math.max(0, _safe.height - _diameter),
    _diameter,
    _diameter,
  );
  Offset get _dismissCenter => Offset(
    _size.width / 2,
    _size.height - MediaQuery.paddingOf(context).bottom - 54,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_presentationChanged);
  }

  @override
  void didUpdateWidget(_FloatingAssistant oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_presentationChanged);
      widget.controller.addListener(_presentationChanged);
    }
  }

  void _presentationChanged() {
    if (!mounted) return;
    if (!widget.controller.visible) {
      _dragging = _overDismiss = false;
      _motion.stop();
    }
    setState(_retarget);
  }

  void _retarget() {
    if (!widget.controller.visible || _dragging || _closing || _size.isEmpty) {
      return;
    }
    final anchor = widget.controller.docking
        ? widget.controller.dockRect
        : null;
    final dock =
        anchor != null && (Offset.zero & _size).contains(anchor.center);
    _moveTo(
      dock ? anchor : _floating,
      dock: dock ? 1 : 0,
      immediate: dock && _toDock == 1 && _motion.isCompleted,
    );
  }

  void _moveTo(Rect target, {required double dock, bool immediate = false}) {
    if (_to == target && _toDock == dock) {
      if (immediate || _reduced) {
        _motion.value = 1;
      } else if (!_motion.isAnimating && !_motion.isCompleted) {
        _motion.forward();
      }
      return;
    }
    _from = _rect ?? target;
    _fromDock = _dock;
    _to = target;
    _toDock = dock;
    if (immediate || _reduced) {
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  Offset _local(Offset global) =>
      (_layer.currentContext!.findRenderObject()! as RenderBox).globalToLocal(
        global,
      );

  void _dragStart(DragStartDetails details) {
    if (_closing) return;
    _grabOffset = _local(details.globalPosition) - _rect!.center;
    _motion.stop();
    setState(() => _dragging = true);
    HapticFeedback.selectionClick();
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final pointer = _local(details.globalPosition) - _grabOffset;
    final over = pointer.dy >= _dismissCenter.dy - 64;
    if (over != _overDismiss) HapticFeedback.selectionClick();
    var center = Offset(
      pointer.dx.clamp(_diameter / 2 + 8, _size.width - _diameter / 2 - 8),
      pointer.dy.clamp(_safe.top + _diameter / 2, _size.height - _diameter / 2),
    );
    if (over && (center - _dismissCenter).distance < 104) {
      center = Offset.lerp(center, _dismissCenter, .55)!;
    }
    setState(() {
      _overDismiss = over;
      _moveTo(
        Rect.fromCenter(center: center, width: _diameter, height: _diameter),
        dock: 0,
        immediate: true,
      );
    });
  }

  void _dragEnd([DragEndDetails? details]) {
    if (!_dragging) return;
    if (_overDismiss) {
      _dismiss();
      return;
    }
    final center = _rect!.center;
    setState(() {
      _dragging = false;
      _resting = Offset(
        center.dx < _size.width / 2 ? 0 : 1,
        ((_rect!.top - _safe.top) / math.max(1, _safe.height - _diameter))
            .clamp(0, 1),
      );
      _retarget();
    });
  }

  void _dragCancel() {
    setState(() {
      _dragging = _overDismiss = false;
      _retarget();
    });
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    HapticFeedback.lightImpact();
    setState(() {
      _dragging = _overDismiss = false;
      _closing = true;
      _moveTo(
        Rect.fromCenter(center: _dismissCenter, width: 20, height: 20),
        dock: 0,
      );
    });
    if (!_reduced) {
      await _motion.forward(from: 0).orCancel.catchError((Object _) {});
    }
    if (!mounted) return;
    widget.controller.dismiss();
    setState(() => _closing = false);
  }

  void _openCompanion() {
    if (_closing || _dragging) return;
    HapticFeedback.mediumImpact();
    widget.navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const CompanionPage()),
    );
  }

  Future<void> _openSheet() async {
    if (_sheetOpen || _closing || _dragging) return;
    final context = widget.navigatorKey.currentState?.overlay?.context;
    if (context == null) return;
    _sheetOpen = true;
    HapticFeedback.selectionClick();
    final pageLabel = widget.controller.pageLabel;
    final contentBuilder = widget.controller.sheetBuilder;
    final companion = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      showDragHandle: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 700),
      builder: (_) => QvacAssistantSheet(
        pageLabel: pageLabel,
        contentBuilder: contentBuilder,
      ),
    );
    _sheetOpen = false;
    if (mounted && companion == true) _openCompanion();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_presentationChanged);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    _reduced = media.disableAnimations;
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final bottom = math.max(media.padding.bottom, media.viewInsets.bottom);
        _safe = Rect.fromLTRB(
          media.padding.left + 14,
          media.padding.top + 14,
          _size.width - media.padding.right - 14,
          math.max(
            media.padding.top + 14 + _diameter,
            _size.height - bottom - (widget.controller.atRoot ? 108 : 24),
          ),
        );
        _retarget();
        if (!widget.controller.visible) return const SizedBox.shrink();
        return Stack(
          key: _layer,
          clipBehavior: Clip.none,
          children: [
            if (_dragging || _closing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 180 + media.padding.bottom,
                child: IgnorePointer(
                  child: _DismissTarget(
                    active: _overDismiss,
                    bottom: media.padding.bottom,
                  ),
                ),
              ),
            AnimatedBuilder(
              animation: _motion,
              builder: (context, _) {
                final rect = _rect!;
                final lift = _dragging || _closing
                    ? 0.0
                    : -18 *
                          math.sin(math.pi * _motion.value) *
                          (_toDock - _fromDock).abs();
                final button = Opacity(
                  opacity: _closing ? 1 - _motion.value : 1,
                  child: RepaintBoundary(
                    child: QvacAssistantButton(
                      dock: _dock,
                      onTap: _openSheet,
                      onLongPress: _openCompanion,
                      onDismiss: _dismiss,
                      onPanStart: _dragStart,
                      onPanUpdate: _dragUpdate,
                      onPanEnd: _dragEnd,
                      onPanCancel: _dragCancel,
                    ),
                  ),
                );
                final following =
                    _toDock == 1 &&
                    _motion.isCompleted &&
                    !_dragging &&
                    !_closing;
                // Keep the same gesture element when detaching from More so
                // starting a drag cannot dispose the active recognizer.
                return Positioned.fromRect(
                  rect: following
                      ? (Offset.zero & rect.size)
                      : rect.shift(Offset(0, lift)),
                  child: CompositedTransformFollower(
                    link: following
                        ? widget.controller.dockLink
                        : _floatingLink,
                    showWhenUnlinked: !following,
                    child: button,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

bool _usesDevice(WidgetRef ref) {
  try {
    return ref.watch(aiRouterProvider).select('summarize-note') ==
        AiProviderKind.device;
  } catch (_) {
    return false;
  }
}

/// One reading of the companion phase, shared by the sticker and the sheet.
({bool connected, bool checking, Color color, String short}) _qvacStatus(
  CompanionPhase phase,
  ColorScheme colors, {
  bool onDevice = false,
}) {
  if (onDevice) {
    return (
      connected: true,
      checking: false,
      color: const Color(0xff619476),
      short: 'On this phone',
    );
  }
  final connected = phase == CompanionPhase.connected;
  final checking = switch (phase) {
    CompanionPhase.loading ||
    CompanionPhase.connecting ||
    CompanionPhase.pairing => true,
    _ => false,
  };
  return (
    connected: connected,
    checking: checking,
    color: connected
        ? const Color(0xff619476)
        : checking
        ? const Color(0xffb68b43)
        : colors.onSurfaceVariant,
    short: connected
        ? 'Connected'
        : checking
        ? 'Checking…'
        : phase == CompanionPhase.idle
        ? 'Not set up'
        : 'Offline',
  );
}

class QvacAssistantButton extends ConsumerWidget {
  const QvacAssistantButton({
    super.key,
    required this.dock,
    required this.onTap,
    required this.onLongPress,
    required this.onDismiss,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });
  final double dock;
  final VoidCallback onTap, onLongPress, onDismiss, onPanCancel;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(
      companionControllerProvider.select((state) => state.phase),
    );
    final colors = Theme.of(context).colorScheme;
    final (:connected, :checking, :color, short: _) = _qvacStatus(
      phase,
      colors,
      onDevice: _usesDevice(ref),
    );
    final label = _usesDevice(ref)
        ? 'On this phone'
        : companionPhaseLabel(phase);
    return Semantics(
      key: const ValueKey('qvac-assistant-button'),
      button: true,
      label: 'Local QVAC, $label',
      hint: 'Tap for page assistance. Hold to open AI companion. Drag to the bottom to hide.',
      onTap: onTap,
      onLongPress: onLongPress,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Hide assistant'): onDismiss,
      },
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        onPanCancel: onPanCancel,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            _QvacSticker(dock: dock, statusColor: color),
            Positioned(
              right: 3 + dock * 4,
              bottom: 3 + dock * 4,
              child: Container(
                key: ValueKey(
                  'qvac-status-${connected
                      ? 'connected'
                      : checking
                      ? 'connecting'
                      : 'disconnected'}',
                ),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: checking && !MediaQuery.disableAnimationsOf(context)
                    ? const SizedBox.square(
                        dimension: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        connected
                            ? Icons.check_rounded
                            : checking
                            ? Icons.more_horiz_rounded
                            : Icons.link_off_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanding the asset's alpha gives the paper edge its exact silhouette,
/// including the little journal note. All layers share the cached image and
/// live inside the button's repaint boundary; there is no idle animation.
class _QvacSticker extends StatelessWidget {
  const _QvacSticker({required this.dock, required this.statusColor});
  final double dock;
  final Color statusColor;

  static const _image = Image(
    image: AssetImage(qvacArtwork),
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );

  Widget _silhouette(ImageFilter filter, Color color) => ImageFiltered(
    imageFilter: filter,
    child: ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: _image,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final floating = 1 - dock;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (floating > 0) ...[
          Transform.translate(
            offset: Offset(0, 2 * floating),
            child: _silhouette(
              ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              Theme.of(context).colorScheme.shadow
                  .withValues(alpha: .24 * floating),
            ),
          ),
          _silhouette(
            ImageFilter.dilate(radiusX: 3 * floating, radiusY: 3 * floating),
            statusColor.withValues(alpha: .65 * floating),
          ),
          _silhouette(
            ImageFilter.dilate(radiusX: 2 * floating, radiusY: 2 * floating),
            const Color(0xfffffcf3).withValues(alpha: floating),
          ),
        ],
        _image,
      ],
    );
  }
}

class _DismissTarget extends StatelessWidget {
  const _DismissTarget({required this.active, required this.bottom});
  final bool active;
  final double bottom;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.surface.withValues(alpha: 0),
            colors.surface.withValues(alpha: .96),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom + 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedScale(
              scale: active ? 1.15 : 1,
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              child: AnimatedContainer(
                key: const ValueKey('qvac-dismiss-target'),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? colors.errorContainer
                      : colors.surfaceContainerHighest,
                  border: Border.all(
                    color: active ? colors.error : colors.outlineVariant,
                  ),
                ),
                child: Icon(
                  Icons.close_rounded,
                  color: active
                      ? colors.onErrorContainer
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              active ? 'Release to hide' : 'Drag here to hide',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Restores sheet scrolling below a Navigator's route-local scroll controller.
/// Retained pages release the shared controller while another page covers them.
/// Outside a QVAC sheet, pages keep their normal scrolling.
class QvacAssistantSheetPage extends StatefulWidget {
  const QvacAssistantSheetPage({super.key, required this.child});
  final Widget child;

  @override
  State<QvacAssistantSheetPage> createState() => _QvacAssistantSheetPageState();
}

class _QvacAssistantSheetPageState extends State<QvacAssistantSheetPage> {
  _QvacSheetScrollScope? _scope;
  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = context
        .dependOnInheritedWidgetOfExactType<_QvacSheetScrollScope>();
    final active = _scope != null && ModalRoute.isCurrentOf(context) != false;
    if (active && !_active) QvacAssistantSheet.expand(context);
    _active = active;
  }

  @override
  Widget build(BuildContext context) {
    if (_scope == null) return widget.child;
    if (!_active) return PrimaryScrollController.none(child: widget.child);
    return PrimaryScrollController(
      controller: _scope!.controller,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: widget.child,
    );
  }
}

class _QvacSheetScrollScope extends InheritedWidget {
  const _QvacSheetScrollScope({required this.controller, required super.child});
  final ScrollController controller;

  @override
  bool updateShouldNotify(_QvacSheetScrollScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Page tools share the sheet's controller so an upward scroll expands the
/// surface before scrolling its content. Settings live in the exposed scrim.
class QvacAssistantSheet extends StatefulWidget {
  const QvacAssistantSheet({
    super.key,
    required this.pageLabel,
    this.contentBuilder,
  });
  final String pageLabel;
  final QvacAssistantSheetBuilder? contentBuilder;

  /// Gives feature pages room without changing the toolbox's initial height.
  /// Outside an assistant sheet, there is nothing to resize.
  static void expand(BuildContext context) {
    final sheet = context.findAncestorStateOfType<_QvacAssistantSheetState>();
    if (sheet == null) return;
    // Wait for the feature's scroll position: detaching the menu's position
    // cancels any sheet animation that was started against it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (sheet.mounted &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent != false) {
        sheet._resize(1);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  State<QvacAssistantSheet> createState() => _QvacAssistantSheetState();
}

class _QvacAssistantSheetState extends State<QvacAssistantSheet> {
  // Flutter compares snap lists by identity. A fresh list on each drag frame
  // restarts snapping and cancels the finger's active drag.
  List<double> get _snapSizes {
    if (!const {'Notes', 'Flow'}.contains(widget.pageLabel) ||
        widget.contentBuilder == null) {
      return const [.64];
    }
    final media = MediaQuery.of(context);
    return media.textScaler.scale(14) > 20 || media.size.height < 600
        ? const [.72]
        : const [.42];
  }

  double get _initialSize => _snapSizes.single;

  final _sheet = DraggableScrollableController();

  // Only reduced motion: Android reports accessible navigation for any
  // accessibility service, not only screen readers.
  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  void _resize(double size) {
    if (!_sheet.isAttached) return;
    if (_reduced) {
      _sheet.jumpTo(size.clamp(.36, 1));
    } else {
      _sheet.animateTo(
        size.clamp(.36, 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: _sheet,
      builder: (context, _) {
        final size = _sheet.isAttached ? _sheet.size : _initialSize;
        final exposed = constraints.maxHeight * (1 - size);
        final colors = Theme.of(context).colorScheme;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                excludeFromSemantics: true,
                onTap: () => Navigator.maybePop(context),
                behavior: HitTestBehavior.opaque,
              ),
            ),
            if (exposed > 76)
              Positioned(
                right: 20,
                bottom: constraints.maxHeight * size + 12,
                child: Opacity(
                  opacity: ((exposed - 76) / 48).clamp(0, 1),
                  child: _SettingsTag(
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: _initialSize,
              minChildSize: .36,
              maxChildSize: 1,
              snap: true,
              snapSizes: _snapSizes,
              builder: (context, scrollController) => Material(
                key: const ValueKey('qvac-sheet-surface'),
                color: const {'Note', 'Notes'}.contains(widget.pageLabel)
                    ? (colors.brightness == Brightness.dark
                          ? const Color(0xFF232522)
                          : const Color(0xFFFAF8F2))
                    : colors.surface,
                elevation: 0,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28 * ((1 - size) / .08).clamp(0, 1)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Semantics(
                      button: true,
                      label: size >= .99 ? 'Collapse sheet' : 'Expand sheet',
                      child: GestureDetector(
                        key: const ValueKey('qvac-sheet-handle'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _resize(size >= .99 ? _initialSize : 1),
                        onVerticalDragUpdate: (details) {
                          if (_sheet.isAttached) {
                            _sheet.jumpTo(
                              (_sheet.size -
                                      details.delta.dy / constraints.maxHeight)
                                  .clamp(.36, 1),
                            );
                          }
                        },
                        onVerticalDragEnd: (details) {
                          if (!_sheet.isAttached) return;
                          final velocity = details.primaryVelocity ?? 0;
                          _resize(
                            velocity < -300 || _sheet.size > .82
                                ? 1
                                : _initialSize,
                          );
                        },
                        child: SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: .35,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _QvacSheetScrollScope(
                        controller: scrollController,
                        child:
                            widget.contentBuilder?.call(
                              context,
                              scrollController,
                            ) ??
                            _QvacPlaceholder(
                              pageLabel: widget.pageLabel,
                              scrollController: scrollController,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Settings stay above the sheet as a status pill on every page.
class _SettingsTag extends ConsumerWidget {
  const _SettingsTag({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final phase = ref.watch(
      companionControllerProvider.select((state) => state.phase),
    );
    final status = _qvacStatus(phase, colors, onDevice: _usesDevice(ref));
    return Semantics(
      key: const ValueKey('qvac-local-ai-settings'),
      button: true,
      label: 'Local AI settings, ${status.short}',
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        elevation: 3,
        shadowColor: colors.shadow.withValues(alpha: .35),
        shape: StadiumBorder(
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 14, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Image.asset(
                        qvacArtwork,
                        width: 34,
                        height: 34,
                        excludeFromSemantics: true,
                      ),
                      PositionedDirectional(
                        end: -1,
                        bottom: -1,
                        child: AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: status.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local AI',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      status.short,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QvacPlaceholder extends ConsumerWidget {
  const _QvacPlaceholder({
    required this.pageLabel,
    required this.scrollController,
  });
  final String pageLabel;
  final ScrollController scrollController;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(
      companionControllerProvider.select((state) => state.phase),
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Image.asset(
                  qvacArtwork,
                  width: 56,
                  height: 56,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your local companion',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        companionPhaseLabel(phase),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              key: const ValueKey('qvac-page-placeholder'),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: colors.primary,
                    size: 28,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A little help with $pageLabel',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This space will adapt to the page you’re on. Tools for $pageLabel are coming soon.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Tip: hold QVAC to open your companion. Drag it to the bottom to tuck it away.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
