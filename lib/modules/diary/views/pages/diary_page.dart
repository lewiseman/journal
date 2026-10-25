import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/views/widgets/diary_header.dart';
import 'package:journal/modules/diary/views/widgets/diary_scene.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key, this.clock});

  /// Override the local clock for previews and deterministic calendar tests.
  final DateTime Function()? clock;

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> with TickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 310,
    damping: 29,
  );
  final _outer = ScrollController();
  final _nested = GlobalKey<NestedScrollViewState>();
  late final _turn = AnimationController.unbounded(vsync: this);
  late final _fade = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 150),
  );
  late DateTime _selectedDate = _today;
  late DiaryDay _day = DiaryDay.sample(_selectedDate);
  late DiaryDay _previous = DiaryDay.sample(diaryDayAfter(_selectedDate, -1));
  DiaryDay? _next;
  DiaryDay? _fadingFrom;
  double _fadingOffset = 0;
  double _cardWidth = 320;
  double _dragDistance = 0;
  int _direction = 1;
  bool _dragging = false;
  bool _settling = false;

  DateTime get _today => diaryDate((widget.clock ?? DateTime.now)());
  bool get _busy => _dragging || _settling;
  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  double get _controlsHeight =>
      (MediaQuery.textScalerOf(context).scale(13) + 26).clamp(
        44.0,
        double.infinity,
      );
  double get _collapseExtent => _controlsHeight + 36;
  double get _outerOffset => _outer.hasClients ? _outer.offset : 0;
  double get _innerOffset {
    final controller = _nested.currentState?.innerController;
    return controller != null && controller.hasClients ? controller.offset : 0;
  }

  bool get _atTop => _outerOffset.abs() < .5 && _innerOffset.abs() < .5;
  bool get _blocked => _direction < 0 && !_selectedDate.isBefore(_today);

  @override
  void initState() {
    super.initState();
    _fade.addStatusListener((status) {
      if (status == AnimationStatus.completed && _fadingFrom != null) {
        setState(() => _fadingFrom = null);
      }
    });
  }

  void _replaceDate(DateTime date, {bool fade = false}) {
    final crossfade = fade && !_reduced;
    final oldDay = _day;
    final oldOffset = _innerOffset;
    // The outer nested controller resets the inner offset while retaining
    // exactly the current header expansion. Jumping the inner one would also
    // collapse the header, even for a short replacement day.
    if (_outer.hasClients) {
      _outer.jumpTo(_outerOffset.clamp(0, _collapseExtent));
    }
    setState(() {
      _selectedDate = date;
      _day = DiaryDay.sample(date);
      _previous = DiaryDay.sample(diaryDayAfter(date, -1));
      _next = null;
      _fadingFrom = crossfade ? oldDay : null;
      _fadingOffset = oldOffset;
    });
    HapticFeedback.selectionClick();
    if (crossfade) _fade.forward(from: 0);
  }

  void _selectDate(DateTime value) {
    final date = diaryDate(value);
    if (_busy || date.isAfter(_today) || date == _selectedDate) return;
    final distance = diaryDaysBetween(_selectedDate, date);
    if (_atTop && distance.abs() == 1 && !_reduced) {
      _direction = distance < 0 ? 1 : -1;
      _settle(commit: true);
    } else {
      _replaceDate(date, fade: true);
    }
  }

  Future<void> _pickDate() async {
    if (_busy) return;
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1),
      lastDate: _today,
    );
    if (date != null && mounted) _selectDate(date);
  }

  void _dragStart(DragStartDetails details) {
    if (!_atTop || _settling) return;
    _dragDistance = 0;
    _fade.value = 1;
    setState(() => _dragging = true);
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _dragDistance += details.delta.dx;
    final direction = _dragDistance < 0 ? -1 : 1;
    if (direction != _direction) setState(() => _direction = direction);
    final progress = _dragDistance.abs() / _cardWidth;
    _turn.value = _blocked
        ? math.min(.12, progress * .16)
        : progress.clamp(0, 1);
  }

  void _dragEnd(DragEndDetails details) {
    if (!_dragging) return;
    final velocity = (details.primaryVelocity ?? 0) * _direction;
    final commit = !_blocked && (_turn.value >= .25 || velocity >= 700);
    _settle(commit: commit, velocity: velocity / _cardWidth);
  }

  Future<void> _settle({required bool commit, double velocity = 0}) async {
    if (_settling) return;
    setState(() {
      _dragging = false;
      _settling = true;
    });
    try {
      if (!_reduced) {
        await _turn
            .animateWith(
              SpringSimulation(
                _spring,
                _turn.value,
                commit ? 1 : 0,
                velocity.clamp(-8.0, 8.0),
                tolerance: const Tolerance(distance: .001, velocity: .001),
              ),
            )
            .orCancel;
      }
      if (!mounted) return;
      if (commit) _replaceDate(diaryDayAfter(_selectedDate, -_direction));
      _turn.value = 0;
      setState(() => _settling = false);
    } on TickerCanceled {
      // Disposing the page never commits an unfinished turn.
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    _fade.dispose();
    _outer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final artworkWidth = width.clamp(0.0, 700.0);
    return Stack(
      children: [
        Positioned(
          top: 100 - artworkWidth * .41,
          left: (width - artworkWidth) / 2,
          width: artworkWidth,
          child: AnimatedBuilder(
            animation: _outer,
            child: Opacity(
              opacity: context.isDark ? .6 : .16,
              child: Image.asset(
                'assets/images/diary_top_bg.png',
                color: context.colors.primary,
                colorBlendMode: BlendMode.color,
                fit: BoxFit.fitWidth,
                excludeFromSemantics: true,
              ),
            ),
            builder: (context, child) => Transform.translate(
              offset: Offset(
                0,
                -28 *
                    Curves.easeOutCubic.transform(
                      (_outerOffset / 120).clamp(0, 1),
                    ),
              ),
              child: child,
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .13, .27, .42, 1],
                colors: [
                  context.colors.surface.withValues(alpha: .627),
                  context.colors.surface.withValues(alpha: .094),
                  context.colors.surface.withValues(alpha: .863),
                  context.colors.surface,
                  context.colors.surface,
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: NestedScrollView(
                key: _nested,
                controller: _outer,
                physics: _busy
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                headerSliverBuilder: (context, innerScrolled) => [
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                    sliver: SliverPersistentHeader(
                      pinned: true,
                      delegate: DiaryHeaderDelegate(
                        topInset: top,
                        selectedDate: _selectedDate,
                        lastDate: _today,
                        controlsHeight: _controlsHeight,
                        onDateChanged: _selectDate,
                        onSearch: null,
                        onPickDate: _pickDate,
                        enabled: !_busy,
                      ),
                    ),
                  ),
                ],
                body: Builder(
                  builder: (context) => AnimatedBuilder(
                    animation: Listenable.merge([_outer, _turn]),
                    builder: (context, _) => DiaryScene(
                      day: _day,
                      previous: _previous,
                      next: () => _next ??= DiaryDay.sample(
                        diaryDayAfter(_selectedDate, 1),
                      ),
                      today: _today,
                      collapse: (_outerOffset / _collapseExtent).clamp(0, 1),
                      headerHeight: top + 82,
                      turn: _turn.value.clamp(0, 1),
                      direction: _direction,
                      busy: _busy,
                      blocked: _blocked,
                      reduced: _reduced,
                      fade: _fade,
                      fadingFrom: _fadingFrom,
                      fadingOffset: _fadingOffset,
                      onCardWidth: (width) => _cardWidth = width,
                      onDateChanged: _selectDate,
                      onDragStart: (_dragging || (!_settling && _atTop))
                          ? _dragStart
                          : null,
                      onDragUpdate: (_dragging || (!_settling && _atTop))
                          ? _dragUpdate
                          : null,
                      onDragEnd: (_dragging || (!_settling && _atTop))
                          ? _dragEnd
                          : null,
                      onDragCancel: _dragging
                          ? () => _settle(commit: false)
                          : null,
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
