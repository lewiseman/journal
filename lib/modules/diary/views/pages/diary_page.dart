import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:journal/common.dart' hide DiaryDayEntity;
import 'package:journal/modules/diary/controllers/diary_search_service.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/views/pages/diary_calendar_page.dart';
import 'package:journal/modules/diary/views/pages/diary_search_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_header.dart';
import 'package:journal/modules/diary/views/widgets/diary_scene.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart'
    show DiaryAccess;
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;

class DiaryPage extends StatelessWidget {
  const DiaryPage({super.key, this.clock, this.diaries});
  final DateTime Function()? clock;
  final List<DiaryDayEntity>? diaries;

  @override
  Widget build(BuildContext context) {
    if (diaries != null) return _DiaryReader(clock: clock, diaries: diaries!);
    return Consumer(
      builder: (context, ref, _) => ref
          .watch(diaryDaysProvider)
          .when(
            data: (days) => DiaryAccess(
              canEdit:
                  ref.watch(syncDeviceRoleProvider) != SyncDeviceRole.secondary,
              today: TimeHelper.dateOnly((clock ?? DateTime.now)()),
              child: _DiaryReader(clock: clock, diaries: days),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load your diary.'),
                  TextButton(
                    onPressed: () => ref.invalidate(diaryDaysProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _DiaryReader extends StatefulWidget {
  const _DiaryReader({this.clock, required this.diaries});
  final DateTime Function()? clock;
  final List<DiaryDayEntity> diaries;
  @override
  State<_DiaryReader> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<_DiaryReader>
    with TickerProviderStateMixin {
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
  List<DiaryDayEntity> get _diaries => widget.diaries;
  late var _days = {for (final day in _diaries) day.dateString: day};
  late DiaryDayEntity _day = _dayFor(_selectedDate);
  late DiaryDayEntity _previous = _dayFor(
    TimeHelper.addDays(_selectedDate, -1),
  );
  DiaryDayEntity? _next;
  DiaryDayEntity? _fadingFrom;
  double _fadingOffset = 0;
  double _cardWidth = 320;
  double _dragDistance = 0;
  int _direction = 1;
  bool _dragging = false;
  bool _settling = false;
  bool _readingTurn = false;

  DateTime get _today => TimeHelper.dateOnly((widget.clock ?? DateTime.now)());
  DiaryDayEntity _dayFor(DateTime date) {
    final key = TimeHelper.dateKey(date);
    final day = _days[key];
    return day != null && !day.isDeleted
        ? day
        : DiaryDayEntity(dateString: key);
  }

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

  @override
  void didUpdateWidget(covariant _DiaryReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.diaries, widget.diaries)) {
      _days = {for (final day in widget.diaries) day.dateString: day};
      _day = _dayFor(_selectedDate);
      _previous = _dayFor(TimeHelper.addDays(_selectedDate, -1));
      _next = _selectedDate.isBefore(_today)
          ? _dayFor(TimeHelper.addDays(_selectedDate, 1))
          : null;
    }
  }

  void _replaceDate(DateTime date, {bool fade = false}) {
    final crossfade = fade && !_reduced;
    final oldDay = _day;
    final neighbors = [_day, _previous, ?_next];
    DiaryDayEntity findDay(DateTime value) => neighbors.firstWhere(
      (day) => day.dateString == TimeHelper.dateKey(value),
      orElse: () => _dayFor(value),
    );
    final oldOffset = _innerOffset;
    // The outer nested controller resets the inner offset while retaining
    // exactly the current header expansion. Jumping the inner one would also
    // collapse the header, even for a short replacement day.
    if (_outer.hasClients) {
      _outer.jumpTo(_outerOffset.clamp(0, _collapseExtent));
    }
    setState(() {
      _selectedDate = date;
      _day = findDay(date);
      _previous = findDay(TimeHelper.addDays(date, -1));
      _next = date.isBefore(_today)
          ? findDay(TimeHelper.addDays(date, 1))
          : null;
      _fadingFrom = crossfade ? oldDay : null;
      _fadingOffset = oldOffset;
    });
    HapticFeedback.selectionClick();
    if (crossfade) _fade.forward(from: 0);
  }

  void _selectDate(DateTime value) {
    final date = TimeHelper.dateOnly(value);
    if (_busy || date.isAfter(_today) || date == _selectedDate) return;
    final distance = TimeHelper.daysBetween(_selectedDate, date);
    if (_atTop && distance.abs() == 1 && !_reduced) {
      _direction = distance < 0 ? 1 : -1;
      _settle(commit: true);
    } else {
      _replaceDate(date, fade: true);
    }
  }

  Future<void> _pickDate() async {
    if (_busy) return;
    final date = await context.nav.push<DateTime>(
      DiaryCalendarPage(
        initialDate: _selectedDate,
        lastDate: _today,
        dayData: (date) =>
            DiaryCalendarDay.fromEntity(_days[TimeHelper.dateKey(date)]),
      ),
      transition: _reduced ? NavTransition.none : NavTransition.platform,
    );
    if (date != null && mounted) _selectDate(date);
  }

  Future<void> _openSearch() async {
    if (_busy) return;
    final date = await context.nav.push<DateTime>(
      DiarySearchPage(
        lastDate: _today,
        service: LocalDiarySearchService(lastDate: _today, diaries: _diaries),
      ),
      transition: _reduced ? NavTransition.none : NavTransition.platform,
    );
    if (date == null || !mounted) return;
    final selected = TimeHelper.dateOnly(date);
    if (selected.isAfter(_today)) return;
    // Search selections reopen the beginning, even for the current day.
    _replaceDate(selected, fade: true);
  }

  void _dragStart(DragStartDetails details) {
    if (!_atTop) return;
    _beginDrag();
  }

  void _calendarDragStart() => _beginDrag(reading: !_atTop);

  void _beginDrag({bool reading = false}) {
    if (_busy) return;
    _dragDistance = 0;
    _fade.value = 1;
    setState(() {
      _dragging = true;
      _readingTurn = reading;
    });
  }

  void _dragUpdate(DragUpdateDetails details) =>
      _updateTurn(details.delta.dx / _cardWidth);

  // Both gestures use fractions of their own surface: one paper width or one
  // calendar tab. They then drive exactly the same turn and spring simulation.
  void _updateTurn(double delta) {
    if (!_dragging) return;
    _dragDistance += delta;
    final direction = _dragDistance < 0 ? -1 : 1;
    if (direction != _direction) setState(() => _direction = direction);
    final progress = _dragDistance.abs();
    _turn.value = _blocked
        ? math.min(.12, progress * .16)
        : progress.clamp(0, 1);
  }

  void _dragEnd(DragEndDetails details) =>
      _endTurn((details.primaryVelocity ?? 0) / _cardWidth);

  void _endTurn(double signedVelocity) {
    if (!_dragging) return;
    final velocity = signedVelocity * _direction;
    final commit =
        !_blocked && (_turn.value >= .25 || velocity >= 700 / _cardWidth);
    _settle(commit: commit, velocity: velocity);
  }

  Future<void> _settle({required bool commit, double velocity = 0}) async {
    if (_settling) return;
    setState(() {
      _dragging = false;
      _settling = true;
    });
    void finishAtEdge() {
      if (commit ? _turn.value >= 1 : _turn.value <= 0) {
        _turn.stop(canceled: false);
      }
    }

    _turn.addListener(finishAtEdge);
    try {
      if (!_reduced && _turn.value != (commit ? 1 : 0)) {
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
      if (commit) {
        _replaceDate(
          TimeHelper.addDays(_selectedDate, -_direction),
          fade: _readingTurn,
        );
      }
      _turn.value = 0;
      setState(() {
        _settling = false;
        _readingTurn = false;
      });
    } on TickerCanceled {
      // Disposing the page never commits an unfinished turn.
    } finally {
      _turn.removeListener(finishAtEdge);
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
    final artworkTop = 60 - artworkWidth * .41;
    final page = Stack(
      children: [
        Positioned(
          top: artworkTop,
          left: (width - artworkWidth) / 2,
          width: artworkWidth,
          child: AnimatedBuilder(
            animation: _outer,
            child: RepaintBoundary(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                // Boost only the top edge and month controls, returning to the
                // existing image opacity before reaching the calendar tabs.
                shaderCallback: (_) =>
                    LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .25, 1],
                      colors: [
                        Colors.white.withValues(
                          alpha: context.isDark ? .94 : .82,
                        ),
                        Colors.white.withValues(
                          alpha: context.isDark ? .94 : .82,
                        ),
                        Colors.white.withValues(
                          alpha: context.isDark ? .68 : .24,
                        ),
                      ],
                    ).createShader(
                      Rect.fromLTWH(
                        0,
                        -artworkTop,
                        artworkWidth,
                        top + _controlsHeight + 20,
                      ),
                    ),
                child: Image.asset(
                  key: const ValueKey('diary-header-artwork'),
                  'assets/images/diary_top_bg.png',
                  color: context.colors.primary,
                  colorBlendMode: BlendMode.color,
                  fit: BoxFit.fitWidth,
                  excludeFromSemantics: true,
                  cacheWidth:
                      (artworkWidth *
                              math.min(
                                2,
                                MediaQuery.devicePixelRatioOf(context),
                              ))
                          .ceil(),
                ),
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
                  context.colors.surface.withValues(alpha: .50),
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
                        onSearch: _openSearch,
                        onPickDate: _pickDate,
                        enabled: !_busy,
                        turn: _turn,
                        turnDirection: _direction,
                        turning: _busy,
                        onDayDragStart: _settling ? null : _calendarDragStart,
                        onDayDragUpdate: _settling ? null : _updateTurn,
                        onDayDragEnd: _settling ? null : _endTurn,
                        onDayDragCancel: _dragging
                            ? () => _settle(commit: false)
                            : null,
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
                      next: () => _next ??= _dayFor(
                        TimeHelper.addDays(_selectedDate, 1),
                      ),
                      today: _today,
                      collapse: (_outerOffset / _collapseExtent).clamp(0, 1),
                      headerHeight: top + 82,
                      collapseExtent: _collapseExtent,
                      turn: _readingTurn ? 0 : _turn.value.clamp(0, 1),
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
    return Listener(
      // An accepted Flutter drag can report a pointer cancellation as an end.
      // Catch it before the gesture recognizer so neither surface commits it.
      onPointerCancel: (_) {
        if (_dragging) _settle(commit: false);
      },
      child: page,
    );
  }
}
