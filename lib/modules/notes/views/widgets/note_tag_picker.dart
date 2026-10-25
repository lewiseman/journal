import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/notes_ctrl.dart';
import '../../models/note_tag.dart';

class NoteTagPicker extends ConsumerStatefulWidget {
  const NoteTagPicker({super.key, required this.currentTags});

  final List<String> currentTags;

  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> currentTags,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (_) => NoteTagPicker(currentTags: currentTags),
    );
  }

  @override
  ConsumerState<NoteTagPicker> createState() => _NoteTagPickerState();
}

class _NoteTagPickerState extends ConsumerState<NoteTagPicker> {
  final _query = TextEditingController();
  final _customEmoji = TextEditingController();
  late final _localTags = <String, NoteTag>{
    for (final tag
        in widget.currentTags.map(NoteTag.tryParse).whereType<NoteTag>())
      tag.key: tag,
  };
  late final _selected = Map<String, NoteTag>.of(_localTags);
  String _emoji = '🏷️';
  String? _emojiError;
  bool _showEmojis = false;

  static const _emojis = [
    ('🏷️', 'Label'),
    ('💡', 'Idea'),
    ('📝', 'Writing'),
    ('💼', 'Work'),
    ('🌱', 'Growth'),
    ('🏡', 'Home'),
    ('❤️', 'Love'),
    ('✨', 'Sparkles'),
    ('📚', 'Books'),
    ('🎯', 'Goal'),
    ('🧠', 'Mind'),
    ('☕', 'Coffee'),
    ('🎨', 'Art'),
    ('🎵', 'Music'),
    ('📷', 'Photos'),
    ('🌍', 'Travel'),
    ('🏃', 'Fitness'),
    ('🍜', 'Food'),
    ('💰', 'Money'),
    ('🛠️', 'Projects'),
    ('🌿', 'Nature'),
    ('🌙', 'Night'),
    ('☀️', 'Sun'),
    ('🔥', 'Fire'),
    ('🧘', 'Calm'),
    ('🎉', 'Celebration'),
    ('🐾', 'Animals'),
    ('💭', 'Thoughts'),
  ];
  static final _emojiPattern = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}'
    r'\u{2190}-\u{21FF}\u{24C2}\u{25A0}-\u{25FF}\u{2934}-\u{2935}'
    r'\u{2B00}-\u{2BFF}\u{20E3}\u{00A9}\u{00AE}\u{203C}\u{2049}'
    r'\u{3030}\u{303D}\u{3297}\u{3299}]',
    unicode: true,
  );

  @override
  void dispose() {
    _query.dispose();
    _customEmoji.dispose();
    super.dispose();
  }

  void _toggle(NoteTag tag) => setState(() {
    if (_selected.containsKey(tag.key)) {
      _selected.remove(tag.key);
    } else {
      _selected[tag.key] = tag;
    }
  });

  void _createTag() {
    final name = _query.text.trim();
    if (name.isEmpty || name.toLowerCase() == 'all' || _emojiError != null) {
      return;
    }
    final tag = NoteTag(name: name, emoji: _emoji);
    setState(() {
      _localTags[tag.key] = tag;
      _selected[tag.key] = tag;
      _query.clear();
      _showEmojis = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _chooseEmoji(String emoji) {
    FocusScope.of(context).unfocus();
    setState(() {
      _emoji = emoji;
      _customEmoji.text = emoji;
      _emojiError = null;
      _showEmojis = false;
    });
  }

  void _readEmoji(String value) {
    final emoji = value.trim();
    final valid = emoji.characters.length == 1 && _emojiPattern.hasMatch(emoji);
    setState(() {
      _emojiError = valid ? null : 'Choose one emoji.';
      if (valid) _emoji = emoji;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final catalog = <String, NoteTag>{
      for (final tag in ref.watch(notesTagProvider))
        if (tag.name.toLowerCase() != 'all')
          tag.name.toLowerCase(): NoteTag(name: tag.name, emoji: tag.emoji),
      ..._localTags,
      ..._selected,
    }.values.toList()..sort((a, b) => a.key.compareTo(b.key));
    final query = _query.text.trim();
    final normalized = query.toLowerCase();
    final matches = catalog
        .where((tag) => tag.key.contains(normalized))
        .toList();
    final reserved = normalized == 'all';
    final canCreate =
        query.isNotEmpty &&
        !reserved &&
        !catalog.any((tag) => tag.key == normalized);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Tags',
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel tags',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      key: const ValueKey('tag-search'),
                      controller: _query,
                      maxLength: 32,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {
                        _showEmojis = false;
                        _emojiError = null;
                      }),
                      onSubmitted: (_) {
                        if (canCreate) _createTag();
                      },
                      decoration: InputDecoration(
                        hintText: 'Find or create a tag',
                        counterText: '',
                        errorText: reserved
                            ? '“All” is reserved for your collection.'
                            : null,
                        prefixIcon: const Icon(Icons.search_rounded, size: 22),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear tag search',
                                onPressed: () => setState(() {
                                  _query.clear();
                                  _showEmojis = false;
                                  _emojiError = null;
                                }),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (matches.isNotEmpty)
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in matches)
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: FilterChip(
                                  selected: _selected.containsKey(tag.key),
                                  showCheckmark: false,
                                  avatar: Text(
                                    tag.emoji,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          tag.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_selected.containsKey(tag.key)) ...[
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                        ),
                                      ],
                                    ],
                                  ),
                                  labelStyle: text.labelLarge?.copyWith(
                                    color: _selected.containsKey(tag.key)
                                        ? colors.onPrimaryContainer
                                        : colors.onSurface,
                                  ),
                                  selectedColor: colors.primaryContainer,
                                  backgroundColor: colors.surface,
                                  side: BorderSide(
                                    color: _selected.containsKey(tag.key)
                                        ? colors.primary.withValues(alpha: .5)
                                        : colors.outlineVariant,
                                  ),
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 9,
                                  ),
                                  onSelected: (_) => _toggle(tag),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (catalog.isEmpty && query.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Type a name to make your first tag.',
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (canCreate) ...[
                      if (matches.isNotEmpty) const SizedBox(height: 20),
                      _creator(query),
                    ],
                    if (_showEmojis && canCreate) ...[
                      const SizedBox(height: 16),
                      _emojiChooser(),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _selected.values.map((tag) => tag.encoded).toList(),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Apply tags'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _creator(String name) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
          final create = TextButton(
            onPressed: _emojiError == null ? _createTag : null,
            child: const Text('Create'),
          );
          final details = Row(
            children: [
              Tooltip(
                message: 'Choose tag emoji',
                child: Semantics(
                  label: 'Choose tag emoji, $_emoji',
                  button: true,
                  child: Material(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _showEmojis = !_showEmojis;
                          _customEmoji.text = _emoji;
                          _emojiError = null;
                        });
                      },
                      child: SizedBox.square(
                        dimension: 52,
                        child: Stack(
                          children: [
                            Center(
                              child: Text(
                                _emoji,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                            Positioned(
                              right: 3,
                              bottom: 3,
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (!largeText) ...[const SizedBox(width: 8), create],
            ],
          );
          if (!largeText) return details;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [details, const SizedBox(height: 8), create],
          );
        },
      ),
    );
  }

  Widget _emojiChooser() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final (emoji, label) in _emojis)
              Semantics(
                selected: _emoji == emoji,
                child: TextButton(
                  onPressed: () => _chooseEmoji(emoji),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(44),
                    backgroundColor: _emoji == emoji
                        ? colors.primaryContainer
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    emoji,
                    semanticsLabel: label,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('custom-tag-emoji'),
          controller: _customEmoji,
          maxLength: 1,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onChanged: _readEmoji,
          onSubmitted: (value) {
            _readEmoji(value);
            if (_emojiError == null) _chooseEmoji(value.trim());
          },
          decoration: InputDecoration(
            labelText: 'Or type your own emoji',
            counterText: '',
            errorText: _emojiError,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}
