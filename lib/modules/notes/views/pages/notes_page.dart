import 'dart:async';

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/notes/models/note_tag.dart';
import 'package:journal/modules/notes/views/widgets/note_card.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/notes/views/widgets/notes_assistant.dart';
import 'package:journal/modules/recall/recall_question_page.dart';
import 'package:journal/modules/notes/views/widgets/note_tag_strip.dart';
import 'package:journal/modules/notes/views/widgets/notes_top_artwork.dart';
import 'package:journal/modules/recall/hybrid_retriever.dart';
import 'package:journal/modules/recall/recall_contract.dart';

class NotesPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  String _query = '';
  String _selectedTag = 'All';

  /// S03b: note UUIDs in hybrid (keyword + meaning) order for [_rankedFor].
  List<String> _ranked = const [];
  String? _rankedFor, _rankNote;
  Timer? _rankTimer;

  @override
  void dispose() {
    _rankTimer?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    setState(() => _query = value);
    _rankTimer?.cancel();
    final query = value.trim();
    if (query.isEmpty) return;
    _rankTimer = Timer(const Duration(milliseconds: 350), () async {
      final notes = ref.read(notesStreamProvider).value ?? const [];
      final result = await ref
          .read(hybridRetrieverProvider)
          .search(
            query,
            sources: RecallSource.notes(notes),
            kinds: const {RecallKind.note},
            limit: 60,
          );
      if (!mounted || _query.trim() != query) return;
      setState(() {
        _ranked = [for (final h in result.hits) h.source.id];
        _rankedFor = query;
        _rankNote = result.fallback;
      });
    });
  }

  List<NoteEntity> _visibleNotes(List<NoteEntity> notes) {
    final result = notes.where((note) {
      if (note.deletedAt != null) return false;
      return _selectedTag == 'All' ||
          note.tags.any(
            (tag) => NoteTag.tryParse(tag)?.key == _selectedTag.toLowerCase(),
          );
    }).toList();
    final query = _query.trim();
    if (query.isNotEmpty) {
      // Keyword ranking shows at once; the hybrid order replaces it shortly.
      final order = _rankedFor == query
          ? _ranked
          : [
              for (final h in HybridRetriever.keywordHits(
                query,
                sources: RecallSource.notes(result),
                kinds: const {RecallKind.note},
                limit: 60,
              ))
                h.source.id,
            ];
      final byUuid = {for (final note in result) note.uuid: note};
      return [for (final uuid in order) ?byUuid[uuid]];
    }
    // Keep the repository's ordering within each group.
    return [
      ...result.where((note) => note.isPinned),
      ...result.where((note) => !note.isPinned),
    ];
  }

  void _startIdeaNote(String idea) {
    if (!mounted || ref.read(accountResetProvider).blocksDataAccess) return;
    context.nav.push(EditNotePage(starterTitle: idea));
  }

  void _openNoteSearch() {
    if (!mounted || ref.read(accountResetProvider).blocksDataAccess) return;
    context.nav.push(const RecallQuestionPage(kind: RecallKind.note));
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesStreamProvider);
    final screenPadding = MediaQuery.paddingOf(context);
    final noteTags = ref.watch(notesTagProvider);
    return QvacAssistantContent(
      label: 'Notes',
      builder: (_, scrollController) => NotesAssistant(
        scrollController: scrollController,
        onUseIdea: _startIdeaNote,
        onSearch: _openNoteSearch,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width.clamp(0.0, 900.0),
                height: 280 + screenPadding.top,
                child: AnimatedBuilder(
                  animation: _scroll,
                  child: const NotesTopArtwork(),
                  builder: (context, child) {
                    final progress = _scroll.hasClients
                        ? (_scroll.offset / 260).clamp(0.0, 1.0)
                        : 0.0;
                    return TickerMode(
                      enabled: progress < 1,
                      child: Opacity(
                        opacity: 1 - progress,
                        child: Transform.translate(
                          offset: Offset(0, -28 * progress),
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  final columns = constraints.maxWidth < 300 || textScale > 1.4
                      ? (constraints.maxWidth >= 650 ? 2 : 1)
                      : (constraints.maxWidth >= 700 ? 3 : 2);

                  return CustomScrollView(
                    key: const PageStorageKey('notes-collection'),
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverFloatingHeader(
                        snapMode: FloatingHeaderSnapMode.overlay,
                        animationStyle: const AnimationStyle(
                          duration: Duration(milliseconds: 220),
                          reverseDuration: Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeOutCubic,
                        ),
                        child: _buildSearch(screenPadding: screenPadding),
                      ),
                      SliverToBoxAdapter(
                        child: Center(
                          child: NoteTagStrip(
                            tags: noteTags,
                            selectedTag: _selectedTag,
                            isLoading: notesAsync.isLoading,
                            onSelected: (tag) =>
                                setState(() => _selectedTag = tag),
                          ),
                        ),
                      ),
                      ...notesAsync.when(
                        skipLoadingOnRefresh: false,
                        loading: () => [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(72),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: context.colors.primary,
                                  semanticsLabel: 'Loading notes',
                                ),
                              ),
                            ),
                          ),
                        ],
                        error: (_, _) => [
                          SliverToBoxAdapter(
                            child: _CollectionMessage(
                              icon: Icon(
                                Icons.cloud_off_rounded,
                                size: 36,
                                color: context.colors.primary,
                              ),
                              title: 'Your notes need a moment',
                              message: 'We couldn\'t load them. Give it another try.',
                              action: 'Try again',
                              onAction: () =>
                                  ref.invalidate(notesRepositoryProvider),
                            ),
                          ),
                        ],
                        data: (allNotes) =>
                            _buildCollection(allNotes, columns, noteTags),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 110 + MediaQuery.paddingOf(context).bottom,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            right: 16,
            child: _AddNoteButton(
              key: const ValueKey('notes-add-button'),
              onPressed: () {
                context.nav.push(EditNotePage());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch({required EdgeInsets screenPadding}) => AnimatedBuilder(
    animation: _scroll,
    builder: (context, child) {
      final raised = _scroll.hasClients
          ? (_scroll.offset / 72).clamp(0.0, 1.0)
          : 0.0;
      final horizontalPadding = 30.0 - 12.0 * raised;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              context.colors.surface.withValues(alpha: raised),
              context.colors.surface.withValues(alpha: .85 * raised),
              context.colors.surface.withValues(alpha: 0),
            ],
            stops: const [0, .5, 1],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: horizontalPadding,
            right: horizontalPadding,
            top: screenPadding.top + 12,
            bottom: 6,
          ),
          child: Material(
            color: Color.lerp(
              context.colors.surfaceContainerLow,
              context.colors.surfaceContainerHigh,
              raised,
            ),
            elevation: 8 * raised,
            shadowColor: context.colors.shadow.withValues(alpha: .2),
            borderRadius: BorderRadius.circular(999),
            child: child,
          ),
        ),
      );
    },
    child: TextField(
      controller: _search,
      keyboardAppearance: Theme.of(context).brightness,
      onChanged: _setQuery,
      style: TextStyle(color: context.colors.onSurface, fontSize: 14),
      cursorColor: context.colors.primary,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        hintText: 'Search notes…',
        hintStyle: TextStyle(
          color: context.colors.onSurfaceVariant,
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: context.colors.primary,
          size: 22,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_query.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _search.clear();
                  _setQuery('');
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: context.colors.onSurfaceVariant,
                  size: 18,
                ),
              ),
            // _buildSortMenu(),
          ],
        ),
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: context.colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: context.colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: context.colors.primary),
        ),
      ),
    ),
  );

  List<Widget> _buildCollection(
    List<NoteEntity> allNotes,
    int columns,
    List<({String emoji, String name})> noteTags,
  ) {
    final entries = _visibleNotes(allNotes);
    final emptyNotebook =
        _selectedTag == 'All' && _query.trim().isEmpty && entries.isEmpty;
    return [
      if (entries.isEmpty && !emptyNotebook)
        SliverToBoxAdapter(
          child: _CollectionMessage(
            icon: _query.trim().isNotEmpty
                ? Icon(
                    Icons.search_off_rounded,
                    size: 36,
                    color: context.colors.primary,
                  )
                : Text(
                    noteTags
                            .where((x) => x.name == _selectedTag)
                            .firstOrNull
                            ?.emoji ??
                        '',
                    style: TextStyle(fontSize: 36),
                  ),
            title: _query.trim().isNotEmpty
                ? 'No matching thoughts'
                : 'A little room to spare',
            message: _query.trim().isNotEmpty
                ? 'Try another word or look in a different collection.'
                : '',
            action: 'Show all notes',
            onAction: () {
              _search.clear();
              _setQuery('');
              setState(() => _selectedTag = 'All');
            },
          ),
        )
      else ...[
        if (_query.trim().isNotEmpty && _rankNote != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                _rankNote!,
                key: const ValueKey('notes-search-note'),
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(top: 10),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childCount: emptyNotebook ? 1 : entries.length,
            itemBuilder: (context, index) {
              if (emptyNotebook) {
                return _FirstNoteCard(
                  onTap: () {
                    context.nav.push(EditNotePage());
                  },
                );
              }
              final note = entries[index];
              return NoteCard(
                key: ValueKey(note.uuid),
                note: note,
                index: index,
                onTap: () {
                  context.nav.push(EditNotePage(existingNote: note));
                },
              );
            },
          ),
        ),
      ],
    ];
  }
}

class _AddNoteButton extends StatefulWidget {
  const _AddNoteButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_AddNoteButton> createState() => _AddNoteButtonState();
}

class _AddNoteButtonState extends State<_AddNoteButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return Tooltip(
      message: 'Add note',
      excludeFromSemantics: true,
      child: Semantics(
        label: 'Add note',
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (pressed) {
              if (_pressed == pressed) return;
              setState(() => _pressed = pressed);
            },
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: context.colors.primary.withValues(alpha: .14),
            child: SizedBox.square(
              dimension: 72,
              child: Center(
                child: AnimatedScale(
                  scale: _pressed ? .94 : 1,
                  duration: reducedMotion
                      ? Duration.zero
                      : Duration(milliseconds: _pressed ? 70 : 140),
                  curve: Curves.easeOutCubic,
                  child: Image.asset(
                    'assets/images/notes_add.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
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

class _CollectionMessage extends StatelessWidget {
  const _CollectionMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });
  final Widget icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
    child: Column(
      children: [
        icon,
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.onSurface,
            fontSize: 21,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: context.colors.primary,
            minimumSize: const Size(48, 48),
          ),
          child: Text(action),
        ),
      ],
    ),
  );
}

class _FirstNoteCard extends StatelessWidget {
  const _FirstNoteCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.secondaryContainer,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.edit_note_rounded,
              color: context.colors.primary,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              'Every idea\nstarts somewhere.',
              style: TextStyle(
                color: context.colors.onSecondaryContainer,
                fontSize: 18,
                height: 1.25,
                letterSpacing: -.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'A list, a plan, a passing thought. Make a little space for it.',
              style: TextStyle(
                color: context.colors.onSecondaryContainer,
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your first note',
                    style: TextStyle(
                      color: context.colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.north_east_rounded,
                  color: context.colors.primary,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
