import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

DateTime _month(DateTime date) => DateTime(date.year, date.month);
int _monthIndex(DateTime date) => date.year * 12 + date.month - 1;
String _dateKey(DateTime date) => date.toIso8601String();

/// A calendar route returns a civil date, or null when dismissed with Back.
class DiaryCalendarPage extends StatefulWidget {
  const DiaryCalendarPage({
    super.key,
    required this.initialDate,
    required this.lastDate,
    this.firstDate,
    this.dayData = DiaryCalendarDay.sample,
  });

  final DateTime initialDate;
  final DateTime lastDate;
  final DateTime? firstDate;
  final DiaryCalendarDay Function(DateTime) dayData;

  @override
  State<DiaryCalendarPage> createState() => _DiaryCalendarPageState();
}

class _DiaryCalendarPageState extends State<DiaryCalendarPage> {
  late final _pages = PageController(
    initialPage: _selectedDate.year - _firstDate.year,
  );
  late int _year = _selectedDate.year;
  final _yearOffsets = <int, double>{};
  final _yearMonths = <int, DateTime>{};
  final _currentYear = GlobalKey<_CalendarYearState>();
  bool _returning = false;

  DateTime get _firstDate => diaryDate(widget.firstDate ?? DateTime(1));
  DateTime get _lastDate => diaryDate(widget.lastDate);
  DateTime get _selectedDate => diaryDate(widget.initialDate);
  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  void _select(DateTime date) {
    if (_returning || date.isBefore(_firstDate) || date.isAfter(_lastDate)) {
      return;
    }
    _returning = true;
    context.nav.pop<DateTime>(date);
  }

  void _showYear(int year, {bool animate = true}) {
    final index = year - _firstDate.year;
    if (_reduced || !animate || (year - _year).abs() > 1) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _today() {
    _yearMonths[_lastDate.year] = _month(_lastDate);
    _yearOffsets[_lastDate.year] = 0;
    _showYear(_lastDate.year, animate: false);
    final current = _currentYear.currentState;
    if (current != null) {
      current.showMonth(_month(_lastDate));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _currentYear.currentState?.showMonth(_month(_lastDate));
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          Positioned(
            top: -150,
            left: 0,
            right: 0,
            height: 420,
            child: IgnorePointer(
              child: Opacity(
                opacity: context.isDark ? .12 : .065,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                  ).createShader(bounds),
                  child: Image.asset(
                    'assets/images/diary_top_bg.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Seven 44px targets still fit on a 320px-wide phone.
                    final inset = constraints.maxWidth < 350 ? 6.0 : 16.0;
                    return Column(
                      children: [
                        _header(context, inset),
                        _CalendarYearTabs(
                          firstYear: _firstDate.year,
                          lastYear: _lastDate.year,
                          year: _year,
                          onSelected: _showYear,
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(inset, 12, inset, 10),
                          child: ExcludeSemantics(
                            child: Row(
                              children: [
                                for (var day = 0; day < 7; day++)
                                  Expanded(
                                    child: Text(
                                      DateFormat.E(locale)
                                          .format(DateTime(2024, 1, 1 + day)),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: colors.onSurfaceVariant
                                            .withValues(alpha: .7),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: PageView.builder(
                            key: const ValueKey('calendar-year-pages'),
                            controller: _pages,
                            itemCount: _lastDate.year - _firstDate.year + 1,
                            onPageChanged: (index) =>
                                setState(() => _year = _firstDate.year + index),
                            itemBuilder: (context, index) {
                              final year = _firstDate.year + index;
                              final initial = year == _selectedDate.year
                                  ? _selectedDate
                                  : year == _lastDate.year
                                  ? _lastDate
                                  : DateTime(
                                      year,
                                      year == _firstDate.year
                                          ? _firstDate.month
                                          : 1,
                                    );
                              return _CalendarYear(
                                key: year == _lastDate.year
                                    ? _currentYear
                                    : ValueKey('calendar-year-page-$year'),
                                initialMonth:
                                    _yearMonths[year] ?? _month(initial),
                                firstDate: _firstDate,
                                lastDate: _lastDate,
                                selectedDate: _selectedDate,
                                inset: inset,
                                offset: _yearOffsets[year] ?? 0,
                                onOffset: (offset) =>
                                    _yearOffsets[year] = offset,
                                dayData: widget.dayData,
                                onSelect: _select,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, double inset) {
    final largeType = MediaQuery.textScalerOf(context).scale(12) > 18;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 6, inset, 0),
      child: Column(
        children: [
          Row(
            children: [
              BackButton(onPressed: () => context.nav.pop()),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '',
                  style: TextStyle(
                    fontSize: 20,
                    letterSpacing: -.8,
                    fontWeight: FontWeight.w500,
                    color: context.colors.onSurface,
                  ),
                ),
              ),
              if (largeType)
                IconButton(
                  key: const ValueKey('calendar-today'),
                  onPressed: _today,
                  tooltip: 'Go to today',
                  icon: const Icon(Icons.today_outlined),
                )
              else
                TextButton.icon(
                  key: const ValueKey('calendar-today'),
                  onPressed: _today,
                  icon: const Icon(Icons.today_outlined, size: 17),
                  label: const Text('Today'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarYearTabs extends StatefulWidget {
  const _CalendarYearTabs({
    required this.firstYear,
    required this.lastYear,
    required this.year,
    required this.onSelected,
  });

  final int firstYear, lastYear, year;
  final ValueChanged<int> onSelected;

  @override
  State<_CalendarYearTabs> createState() => _CalendarYearTabsState();
}

class _CalendarYearTabsState extends State<_CalendarYearTabs> {
  ScrollController? _scroll;
  double _extent = 76;

  void _centerYear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(_scroll?.hasClients ?? false)) return;
      final offset = (widget.year - widget.firstYear) * _extent;
      final reduced =
          MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context);
      if (reduced) {
        _scroll!.jumpTo(offset);
      } else {
        _scroll!.animateTo(
          offset,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void didUpdateWidget(_CalendarYearTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year) _centerYear();
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final extent = math.max(76.0, scaler.scale(16) * 3 + 24);
    if (_extent != extent) {
      _extent = extent;
      _centerYear();
    }
    _scroll ??= ScrollController(
      initialScrollOffset: (widget.year - widget.firstYear) * _extent,
    );
    return SizedBox(
      height: math.max(52.0, scaler.scale(16) * 1.25 + 24),
      child: LayoutBuilder(
        builder: (context, constraints) => ListView.builder(
          key: const ValueKey('calendar-year-tabs'),
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          itemExtent: _extent,
          itemCount: widget.lastYear - widget.firstYear + 1,
          padding: EdgeInsets.symmetric(
            horizontal: math.max(0, (constraints.maxWidth - _extent) / 2),
          ),
          itemBuilder: (context, index) {
            final year = widget.firstYear + index;
            final selected = year == widget.year;
            final colors = context.colors;
            return Semantics(
              selected: selected,
              button: true,
              label: 'Year $year',
              onTap: () => widget.onSelected(year),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('calendar-year-tab-$year'),
                    onTap: () => widget.onSelected(year),
                    excludeFromSemantics: true,
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: selected
                          ? DiaryPaperStamp(
                              paper: colors.primaryContainer,
                              ink: colors.primary,
                              shadowColor: colors.shadow,
                              edgeScale: .45,
                            )
                          : null,
                      child: Center(
                        child: Text(
                          '$year',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Each horizontal year page retains its own vertical position without keeping
/// an ever-growing collection of offscreen calendar widgets alive.
class _CalendarYear extends StatefulWidget {
  const _CalendarYear({
    super.key,
    required this.initialMonth,
    required this.firstDate,
    required this.lastDate,
    required this.selectedDate,
    required this.inset,
    required this.offset,
    required this.onOffset,
    required this.dayData,
    required this.onSelect,
  });

  final DateTime initialMonth, firstDate, lastDate, selectedDate;
  final double inset, offset;
  final ValueChanged<double> onOffset;
  final DiaryCalendarDay Function(DateTime) dayData;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_CalendarYear> createState() => _CalendarYearState();
}

class _CalendarYearState extends State<_CalendarYear> {
  static const _center = ValueKey('calendar-forward-months');
  late DateTime _anchor = widget.initialMonth;
  late final ScrollController _scroll = ScrollController(
    keepScrollOffset: false,
    initialScrollOffset: widget.offset,
  )..addListener(() => widget.onOffset(_scroll.offset));

  void showMonth(DateTime month) {
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_anchor != month) {
      setState(() => _anchor = month);
      _scroll.jumpTo(0);
    } else if (reduced) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _buildMonth(DateTime month) => _CalendarMonth(
    key: ValueKey('calendar-month-${_dateKey(month)}'),
    month: month,
    firstDate: widget.firstDate,
    lastDate: widget.lastDate,
    selectedDate: widget.selectedDate,
    inset: widget.inset,
    dayData: widget.dayData,
    onSelect: widget.onSelect,
  );

  @override
  Widget build(BuildContext context) {
    final firstMonth = _anchor.year == widget.firstDate.year
        ? _month(widget.firstDate)
        : DateTime(_anchor.year);
    final lastMonth = _anchor.year == widget.lastDate.year
        ? _month(widget.lastDate)
        : DateTime(_anchor.year, 12);
    return CustomScrollView(
      key: const ValueKey('diary-calendar-scroll'),
      controller: _scroll,
      center: _center,
      slivers: [
        SliverList.builder(
          itemCount: _monthIndex(_anchor) - _monthIndex(firstMonth),
          itemBuilder: (context, index) =>
              _buildMonth(DateTime(_anchor.year, _anchor.month - index - 1)),
        ),
        SliverList.builder(
          key: _center,
          itemCount: _monthIndex(lastMonth) - _monthIndex(_anchor) + 1,
          itemBuilder: (context, index) =>
              _buildMonth(DateTime(_anchor.year, _anchor.month + index)),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _CalendarMonth extends StatelessWidget {
  const _CalendarMonth({
    super.key,
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.selectedDate,
    required this.inset,
    required this.dayData,
    required this.onSelect,
  });

  final DateTime month, firstDate, lastDate, selectedDate;
  final double inset;
  final DiaryCalendarDay Function(DateTime) dayData;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final nextMonth = DateTime(month.year, month.month + 1);
    final end = nextMonth.isAfter(lastDate)
        ? lastDate
        : diaryDayAfter(nextMonth, -1);
    final monday = diaryDayAfter(month, 1 - month.weekday);
    final weeks = (diaryDaysBetween(monday, end) + 1 + 6) ~/ 7;
    // The lower inset keeps the sticker's overhang inside the day's tap area.
    final dayHeight =
        math.max(54.0, MediaQuery.textScalerOf(context).scale(16) * 1.25 + 34) +
        16;
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (month.month == 1) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 22, 8, 12),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text(
                      '${month.year}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        color: colors.primary,
                      ),
                    ),
                    if (!DateTime(month.year + 1).isAfter(lastDate))
                      _SummaryLink(
                        key: ValueKey('calendar-year-summary-${month.year}'),
                        label: 'Year summary',
                        description: '${month.year}',
                      ),
                  ],
                ),
              ),
              Divider(color: colors.primary.withValues(alpha: .14), height: 1),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${month.year}',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.8,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        DateFormat.MMMM(locale).format(month),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -.9,
                        ),
                      ),
                    ],
                  );
                  final summary = !nextMonth.isAfter(lastDate)
                      ? _SummaryLink(
                          key: ValueKey(
                            'calendar-month-summary-${_dateKey(month)}',
                          ),
                          label: 'Month summary',
                          description: MaterialLocalizations.of(context)
                              .formatMonthYear(month),
                        )
                      : null;
                  if (MediaQuery.textScalerOf(context).scale(12) > 18) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, ?summary],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      ?summary,
                    ],
                  );
                },
              ),
            ),
            for (var week = 0; week < weeks; week++) ...[
              SizedBox(
                height: dayHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var day = 0; day < 7; day++)
                      Expanded(
                        child: _day(
                          context,
                          diaryDayAfter(monday, week * 7 + day),
                        ),
                      ),
                  ],
                ),
              ),
              if (_weekComplete(diaryDayAfter(monday, week * 7 + 6)))
                _weekSummary(context, diaryDayAfter(monday, week * 7), locale)
              else if (week < weeks - 1)
                const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  // A week spanning two months belongs to the month containing its Sunday.
  bool _weekComplete(DateTime sunday) =>
      sunday.month == month.month && sunday.isBefore(lastDate);

  Widget _weekSummary(BuildContext context, DateTime monday, String locale) {
    final sunday = diaryDayAfter(monday, 6);
    final range =
        '${DateFormat.MMMd(locale).format(monday)} – ${DateFormat.MMMd(locale).format(sunday)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              range,
              style: TextStyle(
                fontSize: 9,
                color: context.colors.onSurfaceVariant.withValues(alpha: .65),
              ),
            ),
          ),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: _SummaryLink(
                key: ValueKey('calendar-week-summary-${_dateKey(monday)}'),
                label: 'Week summary',
                description:
                    '${MaterialLocalizations.of(context).formatFullDate(monday)} to '
                    '${MaterialLocalizations.of(context).formatFullDate(sunday)}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _day(BuildContext context, DateTime date) {
    if (date.month != month.month ||
        date.isBefore(firstDate) ||
        date.isAfter(lastDate)) {
      return const SizedBox.expand();
    }
    return _CalendarDate(
      key: ValueKey('calendar-day-${_dateKey(date)}'),
      date: date,
      data: dayData(date),
      selected: date == selectedDate,
      today: date == lastDate,
      onTap: () => onSelect(date),
    );
  }
}

class _SummaryLink extends StatelessWidget {
  const _SummaryLink({
    super.key,
    required this.label,
    required this.description,
  });

  final String label, description;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label, $description',
    onTap: _noop,
    excludeSemantics: true,
    child: TextButton(
      // These entry points intentionally have no destination in this UI pass.
      onPressed: _noop,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        textStyle: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontSize: 10, fontWeight: FontWeight.w500),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label)),
          const SizedBox(width: 5),
          const Icon(Icons.north_east_rounded, size: 12),
        ],
      ),
    ),
  );

  static void _noop() {}
}

class _CalendarDate extends StatefulWidget {
  const _CalendarDate({
    super.key,
    required this.date,
    required this.data,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime date;
  final DiaryCalendarDay data;
  final bool selected, today;
  final VoidCallback onTap;

  @override
  State<_CalendarDate> createState() => _CalendarDateState();
}

class _CalendarDateState extends State<_CalendarDate> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = widget.data;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final ink = widget.selected ? colors.primary : colors.onSurface;
    final paper = widget.selected
        ? colors.primaryContainer
        : Color.alphaBlend(
            colors.primary.withValues(alpha: context.isDark ? .06 : .025),
            colors.surfaceContainerLowest,
          );
    final label = [
      MaterialLocalizations.of(context).formatFullDate(widget.date),
      if (widget.today) 'Today',
      data.hasEntry ? 'Journal entry' : 'No journal entry',
      if (data.mood != null) '${data.mood!.label} mood',
    ].join(', ');
    final tilt =
        (-8 + (widget.date.day * 13 + widget.date.month * 7) % 5 - 2) *
        math.pi /
        180;
    final dateDiameter = math.max(
      25.0,
      MediaQuery.textScalerOf(context).scale(15) * 1.25 + 4,
    );
    return Semantics(
      label: label,
      button: true,
      selected: widget.selected,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(10),
          splashColor: colors.primary.withValues(alpha: .08),
          highlightColor: colors.primary.withValues(alpha: .04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 13),
            child: Center(
              child: AnimatedScale(
                scale: _pressed && !reduced ? .94 : 1,
                duration: reduced
                    ? Duration.zero
                    : Duration(milliseconds: _pressed ? 70 : 180),
                curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 64),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (data.hasEntry || widget.selected)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: DiaryPaperStamp(
                              paper: paper,
                              ink: ink,
                              shadowColor: colors.shadow,
                              variant: widget.date.day,
                              edgeScale: .5,
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            width: dateDiameter,
                            height: dateDiameter,
                            decoration: widget.today
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.primary.withValues(
                                        alpha: .8,
                                      ),
                                    ),
                                  )
                                : null,
                            alignment: Alignment.center,
                            child: Text(
                              '${widget.date.day}',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: widget.selected || widget.today
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color:
                                    data.hasEntry ||
                                        widget.selected ||
                                        widget.today
                                    ? ink
                                    : colors.onSurfaceVariant.withValues(
                                        alpha: .65,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (data.mood != null)
                        Positioned(
                          bottom: -8,
                          left: 2,
                          width: 22,
                          height: 22,
                          child: Transform.rotate(
                            angle: tilt,
                            child: Text(
                              data.mood!.emoji,
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 22,
                                height: 1,
                                shadows: [
                                  Shadow(
                                    color: colors.shadow.withValues(
                                      alpha: context.isDark ? .4 : .2,
                                    ),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                                fontFamilyFallback: const [
                                  'Apple Color Emoji',
                                  'Noto Color Emoji',
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (widget.selected)
                        Positioned(
                          right: -3,
                          top: -6,
                          child: Image.asset(
                            'assets/images/diary_calendar_pin.png',
                            width: 20,
                            height: 20,
                            excludeFromSemantics: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
