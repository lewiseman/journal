import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/notes/models/note_tag.dart';
import 'package:journal/modules/notes/views/widgets/note_card.dart';
import 'package:journal/modules/notes/views/widgets/note_idea_card.dart';
import 'package:journal/modules/notes/views/widgets/note_tag_strip.dart';
import 'package:journal/modules/notes/views/widgets/notes_top_artwork.dart';

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

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  List<NoteEntity> _visibleNotes(List<NoteEntity> notes) {
    final result = notes.where((note) {
      if (note.deletedAt != null) return false;
      if (_selectedTag != 'All' &&
          !note.tags.any(
            (tag) => NoteTag.tryParse(tag)?.key == _selectedTag.toLowerCase(),
          )) {
        return false;
      }
      return (_query.isEmpty ||
          '${note.title}\n${note.content}'.toLowerCase().contains(_query));
    }).toList();
    // Keep the repository's ordering within each group.
    return [
      ...result.where((note) => note.isPinned),
      ...result.where((note) => !note.isPinned),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesStreamProvider);
    final screenPadding = MediaQuery.paddingOf(context);
    final noteTags = ref.watch(notesTagProvider);
    return Stack(
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
                            message:
                                'We couldn\'t load them. Give it another try.',
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
          child: FloatingActionButton(
            elevation: 5,
            backgroundColor: context.colors.primaryContainer,
            foregroundColor: context.colors.onPrimaryContainer,
            tooltip: 'Add note',
            child: const Icon(Icons.add_rounded),
            onPressed: () {
              context.nav.push(EditNotePage());
            },
          ),
        ),
      ],
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
      onChanged: (value) => setState(() => _query = value),
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
                  setState(() => _query = '');
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
    final showIdea = _selectedTag == 'All' && _query.trim().isEmpty;
    final emptyNotebook = showIdea && entries.isEmpty;
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
              setState(() {
                _query = '';
                _selectedTag = 'All';
              });
            },
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(top: 10),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childCount: emptyNotebook ? 2 : entries.length + (showIdea ? 1 : 0),
            itemBuilder: (context, index) {
              if (showIdea && index == 1) {
                return NoteIdeaCard(
                  key: const ValueKey('note-idea-shuffle'),
                  onUsePrompt: (prompt) {
                    context.nav.push(EditNotePage(starterTitle: prompt));
                  },
                );
              }
              if (emptyNotebook) {
                return _FirstNoteCard(
                  onTap: () {
                    context.nav.push(EditNotePage());
                  },
                );
              }
              final noteIndex = showIdea && index > 1 ? index - 1 : index;
              final note = entries[noteIndex];
              return NoteCard(
                key: ValueKey(note.uuid),
                note: note,
                index: noteIndex,
                onTap: () {
                  context.nav.push(EditNotePage(existingNote: note));
                },
              );
            },
          ),
        ),
    ];
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
