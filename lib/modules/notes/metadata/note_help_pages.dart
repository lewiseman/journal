import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_tag.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

import '../summary/summary_controller.dart';
import '../summary/summary_page.dart';
import '../summary/summary_history_page.dart';
import 'note_help_contract.dart';

/// What an accepted suggestion replaced, so the editor can offer Undo.
class NoteMetadataUndo {
  const NoteMetadataUndo({
    required this.noteId,
    required this.title,
    required this.tags,
    required this.version,
  });
  final String noteId, title, version;
  final List<String> tags;
}

/// Shown when the shared AI slot holds another kind of task.
class _OtherTask extends StatelessWidget {
  const _OtherTask();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Another AI preview is open. Finish or clear it before asking for new suggestions.',
      ),
      TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NoteSummaryPage()),
        ),
        child: const Text('Open the current preview'),
      ),
    ],
  );
}

class _TaskControls extends ConsumerWidget {
  const _TaskControls();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.busy) const LinearProgressIndicator(),
        if (state.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              state.message!,
              key: const ValueKey('note-help-message'),
            ),
          ),
        if (state.handle != null && !state.terminal && !state.busy)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: controller.retry,
                child: const Text('Retry / retrieve same task'),
              ),
              TextButton(
                onPressed: controller.cancel,
                child: const Text('Cancel task'),
              ),
            ],
          ),
        if (state.handle == null && state.phase != 'idle' && !state.busy)
          TextButton(
            onPressed: state.phase == 'storageError'
                ? controller.restore
                : controller.clear,
            child: const Text('Return'),
          ),
      ],
    );
  }
}

class NoteMetadataPage extends ConsumerStatefulWidget {
  const NoteMetadataPage({super.key, required this.noteId});
  final String noteId;
  @override
  ConsumerState<NoteMetadataPage> createState() => _NoteMetadataPageState();
}

class _NoteMetadataPageState extends ConsumerState<NoteMetadataPage> {
  String? _title;
  final _tags = <String>{};

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final readOnly =
        ref.watch(syncDeviceRoleProvider) == SyncDeviceRole.secondary;
    final note = ref
        .watch(notesRepositoryProvider)
        .getNoteByUuid(widget.noteId);
    final library = [
      for (final tag in ref.watch(notesTagProvider))
        if (tag.name != 'All') NoteTag(name: tag.name, emoji: tag.emoji),
    ];
    final mine = handle?.isNoteMetadata == true;
    final suggestions = mine
        ? controller.noteMetadataSuggestions(library: library)
        : null;
    final chosen = [
      for (final tag in suggestions?.tags ?? const <NoteTag>[])
        if (_tags.contains(tag.key)) tag,
    ];
    return NoteAiScaffold(
      tool: NoteAiTool.metadata,
      step: suggestions != null
          ? 2
          : state.busy
          ? 1
          : 0,
      children: [
        if (handle == null && state.phase == 'idle') ...[
          if (note == null || note.isDeleted)
            const Text('This note is no longer available.')
          else if (note.content.trim().isEmpty)
            const Text(
              'Write something in the note body first. Titles and tags are suggested only from what the note says.',
              key: ValueKey('note-metadata-empty'),
            )
          else if (readOnly)
            const Text(
              'Existing notes are read-only on this device, so suggestions cannot be applied here.',
            )
          else
            FilledButton.icon(
              key: const ValueKey('note-metadata-start'),
              onPressed: () => controller.startNoteMetadata(widget.noteId),
              icon: const Icon(Icons.sell_outlined),
              label: const Text('Suggest title & tags'),
            ),
        ],
        if (handle != null && !mine) const _OtherTask(),
        if (mine) ...[
          Text(
            summaryPhaseLabel(state.phase),
            key: const ValueKey('note-metadata-phase'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (handle!.noteId != widget.noteId)
            const Text('These suggestions belong to another note.'),
          if (state.stale)
            const Text(
              'The note changed or was deleted after the request. These suggestions cannot be applied.',
              key: ValueKey('note-metadata-stale'),
            ),
          if (state.text != null && suggestions == null)
            const Text('The suggestions could not be read safely.'),
          if (suggestions != null) ...[
            const SizedBox(height: 16),
            Text('Title', style: Theme.of(context).textTheme.titleSmall),
            ListTile(
              key: const ValueKey('note-metadata-keep-title'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _title == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text('Keep “${note?.title ?? ''}”'),
              onTap: () => setState(() => _title = null),
            ),
            for (final title in suggestions.titles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _title == title
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(title),
                onTap: () => setState(() => _title = title),
              ),
            if (suggestions.titles.isEmpty)
              const Text('No new titles were suggested.'),
            const SizedBox(height: 12),
            Text(
              'Add tags (existing tags are kept)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in suggestions.tags)
                  FilterChip(
                    avatar: Text(tag.emoji),
                    label: Text(tag.name),
                    selected: _tags.contains(tag.key),
                    onSelected: (value) => setState(
                      () => value ? _tags.add(tag.key) : _tags.remove(tag.key),
                    ),
                  ),
              ],
            ),
            if (suggestions.tags.isEmpty)
              const Text('No new tags were suggested.'),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('note-metadata-apply'),
              onPressed:
                  state.stale ||
                      state.busy ||
                      readOnly ||
                      handle.noteId != widget.noteId ||
                      (_title == null && chosen.isEmpty)
                  ? null
                  : () async {
                      final before = note!;
                      final accepted = await controller.acceptNoteMetadata(
                        title: _title,
                        tags: chosen,
                      );
                      if (!context.mounted || !accepted) return;
                      final after = ref
                          .read(notesRepositoryProvider)
                          .getNoteByUuid(widget.noteId);
                      Navigator.of(context).pop(
                        after == null
                            ? null
                            : NoteMetadataUndo(
                                noteId: widget.noteId,
                                title: before.title,
                                tags: List.of(before.tags),
                                version: after.versionVectorJson,
                              ),
                      );
                    },
              child: const Text('Apply selected'),
            ),
          ],
          if (state.terminal)
            TextButton(
              key: const ValueKey('note-metadata-clear'),
              onPressed: state.busy ? null : controller.clear,
              child: const Text('Reject / clear suggestions'),
            ),
        ],
        const _TaskControls(),
      ],
    );
  }
}

class NoteIdeasPage extends ConsumerStatefulWidget {
  const NoteIdeasPage({super.key, this.onUseIdea});

  /// Opens a new note starting with the chosen idea.
  final ValueChanged<String>? onUseIdea;
  @override
  ConsumerState<NoteIdeasPage> createState() => _NoteIdeasPageState();
}

class _NoteIdeasPageState extends ConsumerState<NoteIdeasPage> {
  final _topic = TextEditingController();
  final _selected = <String>[];
  bool _personal = false;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final mine = handle?.isNoteIdeas == true;
    final notes = (ref.watch(notesStreamProvider).asData?.value ?? const [])
        .where(
          (n) => !n.isDeleted && '${n.title}${n.content}'.trim().isNotEmpty,
        )
        .take(30)
        .toList();
    final context_ = [
      for (final id in _selected)
        if (notes.where((n) => n.uuid == id).firstOrNull case final note?)
          NoteIdeaContext.fromNote(note),
    ];
    final ideas = mine ? controller.noteIdeas() : null;
    return NoteAiScaffold(
      tool: NoteAiTool.ideas,
      step: ideas != null
          ? 2
          : state.busy
          ? 1
          : 0,
      children: [
        if (handle == null && state.phase == 'idle') ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('note-ideas-topic'),
            controller: _topic,
            maxLength: noteIdeaTopicChars,
            decoration: const InputDecoration(
              labelText: 'Topic (optional)',
              hintText: 'For example: weekend plans',
            ),
          ),
          SwitchListTile(
            key: const ValueKey('note-ideas-personal'),
            contentPadding: EdgeInsets.zero,
            value: _personal,
            title: const Text('Use notes I choose'),
            subtitle: const Text(
              'Send the title and start of up to 3 notes you pick below.',
            ),
            onChanged: (value) => setState(() {
              _personal = value;
              if (!value) _selected.clear();
            }),
          ),
          if (_personal) ...[
            for (final note in notes)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(note.uuid),
                title: Text(
                  note.title.trim().isEmpty ? 'Untitled' : note.title,
                ),
                onChanged:
                    !_selected.contains(note.uuid) &&
                        _selected.length >= noteIdeaContextNotes
                    ? null
                    : (value) => setState(
                        () => value == true
                            ? _selected.add(note.uuid)
                            : _selected.remove(note.uuid),
                      ),
              ),
            if (context_.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Exactly this will be sent',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final item in context_)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${item.title}\n${item.excerpt}',
                    key: ValueKey('note-ideas-disclosed-${item.noteId}'),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('note-ideas-start'),
            onPressed: () => controller.startNoteIdeas(
              NoteIdeaSource(
                topic: _topic.text,
                notes: _personal ? context_ : const [],
              ),
            ),
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Suggest ideas'),
          ),
        ],
        if (handle != null && !mine) const _OtherTask(),
        if (mine) ...[
          Text(
            summaryPhaseLabel(state.phase),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (state.text != null && ideas == null)
            const Text('The ideas could not be read safely.'),
          for (final idea in ideas ?? const <String>[])
            Card(
              child: ListTile(
                title: Text(idea),
                trailing: const Icon(Icons.arrow_outward_rounded),
                onTap: () async {
                  await controller.clear();
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  widget.onUseIdea?.call(idea);
                },
              ),
            ),
          if (state.terminal)
            TextButton(
              onPressed: state.busy ? null : controller.clear,
              child: const Text('Clear ideas'),
            ),
        ],
        const _TaskControls(),
        const SizedBox(height: 12),
      ],
    );
  }
}
