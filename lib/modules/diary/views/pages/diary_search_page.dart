import 'package:intl/intl.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_search_service.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/models/diary_search_result.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_opening.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_paper.dart';

enum _SearchStage { opening, searching, results, empty, error }

/// Full-screen journal search. Selecting a memory returns its civil diary date.
class DiarySearchPage extends StatefulWidget {
  const DiarySearchPage({super.key, required this.lastDate, this.service});

  final DateTime lastDate;
  final DiarySearchService? service;

  @override
  State<DiarySearchPage> createState() => _DiarySearchPageState();
}

class _DiarySearchPageState extends State<DiarySearchPage> {
  final _draft = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final _service =
      widget.service ?? SampleDiarySearchService(lastDate: widget.lastDate);
  _SearchStage _stage = _SearchStage.opening;
  DiarySearchResult? _result;
  String _submitted = '';
  int _request = 0;
  bool _returning = false;

  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  Future<void> _search([String? prompt]) async {
    final query = (prompt ?? _draft.text).trim();
    if (query.isEmpty ||
        (_stage == _SearchStage.searching && query == _submitted)) {
      return;
    }
    final request = ++_request;
    _draft.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focus.unfocus();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _submitted = query;
      _result = null;
      _stage = _SearchStage.searching;
    });
    try {
      final result = await _service.search(query);
      if (!mounted || request != _request) return;
      setState(() {
        _result = result;
        _stage = result.matches.isEmpty
            ? _SearchStage.empty
            : _SearchStage.results;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _stage = _SearchStage.error);
    }
  }

  void _clear() {
    _request++;
    _draft.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _submitted = '';
      _result = null;
      _stage = _SearchStage.opening;
    });
  }

  void _open(DiarySearchMatch match) {
    final date = diaryDate(match.date);
    if (_returning || date.isAfter(diaryDate(widget.lastDate))) return;
    _returning = true;
    _focus.unfocus();
    context.nav.pop<DateTime>(date);
  }

  @override
  void dispose() {
    _request++;
    _draft.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    body: Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 320,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Stack(
                children: [
                  Positioned(
                    top: -165,
                    left: 0,
                    right: 0,
                    height: 420,
                    child: Opacity(
                      opacity: context.isDark ? .16 : .10,
                      child: Image.asset(
                        'assets/images/diary_top_bg.png',
                        color: context.colors.primary,
                        colorBlendMode: BlendMode.color,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // Reach opaque paper before the image ends at y=255.
                  // Covering that edge avoids a GPU mask seam on devices.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, .45, .72, 1],
                          colors: [
                            context.colors.surface.withValues(alpha: 0),
                            context.colors.surface.withValues(alpha: .65),
                            context.colors.surface,
                            context.colors.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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
                  final compact =
                      constraints.maxHeight < 420 ||
                      MediaQuery.viewInsetsOf(context).bottom > 0;
                  return Column(
                    children: [
                      _header(),
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('diary-search-scroll'),
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                          child: AnimatedSwitcher(
                            duration: _reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                for (final child in previous)
                                  ExcludeSemantics(
                                    child: IgnorePointer(child: child),
                                  ),
                                ?current,
                              ],
                            ),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: _reduced
                                          ? Offset.zero
                                          : const Offset(0, .025),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: SizedBox(
                              key: ValueKey('${_stage.name}-$_request'),
                              width: double.infinity,
                              child: _body(),
                            ),
                          ),
                        ),
                      ),
                      _composer(compact: compact),
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

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 20, 10),
    child: Row(
      children: [
        BackButton(onPressed: () => context.nav.pop()),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Search journal',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: -.5,
              color: context.colors.onSurface,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _body() {
    if (_stage == _SearchStage.opening) {
      return DiarySearchOpening(onSearch: _search, reduced: _reduced);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          '“$_submitted”',
          style: TextStyle(
            fontSize: 23,
            height: 1.35,
            letterSpacing: -.6,
            color: context.colors.onSurface,
          ),
        ),
        const SizedBox(height: 24),
        if (_stage == _SearchStage.searching)
          _message(
            title: 'Looking through the pages…',
            child: const Padding(
              padding: EdgeInsets.only(top: 22, bottom: 8),
              child: LinearProgressIndicator(
                semanticsLabel: 'Searching journal entries',
              ),
            ),
          ),
        if (_stage == _SearchStage.error)
          _message(
            title: 'The pages need a moment.',
            message:
                'Something interrupted this search. Try your question again.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: FilledButton.tonal(
                  key: const ValueKey('diary-search-retry'),
                  onPressed: () => _search(_submitted),
                  child: const Text('Try again'),
                ),
              ),
            ),
          ),
        if (_stage == _SearchStage.empty) ...[
          _message(
            title: 'No moments found yet.',
            message: 'Try a person, a feeling, or a few different words.',
          ),
          const SizedBox(height: 28),
          DiarySearchPrompts(onSearch: _search, reduced: _reduced),
        ],
        if (_stage == _SearchStage.results) ...[
          DiarySearchPaper(
            key: const ValueKey('diary-search-answer'),
            color: context.colors.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 18,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'What I found',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _result!.answer,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.6,
                      color: context.colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '${_result!.matches.length} '
            '${_result!.matches.length == 1 ? 'moment' : 'moments'} to return to',
            style: TextStyle(
              fontSize: 12,
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _result!.matches.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _MemoryCard(
              key: ValueKey('diary-search-match-$i'),
              match: _result!.matches[i],
              variant: i,
              onTap: () => _open(_result!.matches[i]),
            ),
          ],
        ],
      ],
    );
  }

  Widget _message({required String title, String? message, Widget? child}) =>
      DiarySearchPaper(
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 21,
                  height: 1.4,
                  letterSpacing: -.5,
                  color: context.colors.onSurface,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              ?child,
            ],
          ),
        ),
      );

  Widget _composer({required bool compact}) => Padding(
    padding: EdgeInsets.fromLTRB(20, 10, 20, compact ? 8 : 14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DiarySearchPaper(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('diary-search-input'),
                  controller: _draft,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: compact ? 1 : 3,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: context.colors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'What do you remember?',
                    hintStyle: TextStyle(
                      color: context.colors.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    suffixIcon: _draft.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _clear,
                            icon: const Icon(Icons.close_rounded, size: 19),
                          ),
                  ),
                  onChanged: (value) {
                    if (value.isEmpty) {
                      _clear();
                    } else {
                      setState(() {});
                    }
                  },
                  onSubmitted: (_) => _search(),
                ),
              ),
              IconButton.filled(
                key: const ValueKey('diary-search-submit'),
                tooltip: 'Search journal',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _draft.text.trim().isEmpty ? null : () => _search(),
                icon: const Icon(Icons.arrow_upward_rounded, size: 22),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 12),
          Text(
            'A few words can bring a day back.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    super.key,
    required this.match,
    required this.variant,
    required this.onTap,
  });

  final DiarySearchMatch match;
  final int variant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = [
      NoteColorPreset.paper,
      NoteColorPreset.sage,
      NoteColorPreset.lavender,
    ][variant % 3].resolveColors(context.colors);
    final kind = switch (match.kind) {
      DiaryItemKind.reflection => 'Reflection',
      DiaryItemKind.note => 'Note',
      DiaryItemKind.mood => 'Mood',
      DiaryItemKind.checklist => 'Intentions',
    };
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(match.date);
    return DiarySearchPaper(
      color: paper.background,
      variant: variant,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              Text(
                date,
                style: TextStyle(fontSize: 11, color: paper.secondary),
              ),
              Text(
                kind,
                style: TextStyle(fontSize: 11, color: paper.secondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            match.title,
            style: TextStyle(
              fontSize: 21,
              height: 1.25,
              letterSpacing: -.4,
              color: paper.foreground,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            match.excerpt,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, height: 1.6, color: paper.secondary),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Open day',
                  style: TextStyle(fontSize: 12, color: paper.foreground),
                ),
              ),
              Icon(Icons.north_east_rounded, size: 17, color: paper.foreground),
            ],
          ),
        ],
      ),
    );
  }
}
