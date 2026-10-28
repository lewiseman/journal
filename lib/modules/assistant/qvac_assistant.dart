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
    final companion = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) =>
          QvacAssistantSheet(pageLabel: widget.controller.pageLabel),
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
    _reduced = media.disableAnimations || media.accessibleNavigation;
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
    final connected = phase == CompanionPhase.connected;
    final checking = switch (phase) {
      CompanionPhase.loading ||
      CompanionPhase.connecting ||
      CompanionPhase.pairing => true,
      _ => false,
    };
    final color = connected
        ? const Color(0xff619476)
        : checking
        ? const Color(0xffb68b43)
        : colors.onSurfaceVariant;
    final label = companionPhaseLabel(phase);
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
                child:
                    checking &&
                        !MediaQuery.disableAnimationsOf(context) &&
                        !MediaQuery.accessibleNavigationOf(context)
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

/// Replace the placeholder by destination when page-specific widgets land.
class QvacAssistantSheet extends ConsumerWidget {
  const QvacAssistantSheet({super.key, required this.pageLabel});
  final String pageLabel;
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
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Open AI companion'),
            ),
            const SizedBox(height: 12),
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
