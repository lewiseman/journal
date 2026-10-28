import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/notes/summary/summary_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;

import 'note_website_view.dart';
import 'website_contract.dart';

/// The Markdown formatting operation this page offers.
const _markdownOperation = 'markdown-note';

enum NotePresentationMode { website, markdown }

/// Chooses how a saved note is presented: as a generated website kept beside
/// its text, or with its text reformatted as Markdown in place.
class NotePresentationPage extends ConsumerStatefulWidget {
  const NotePresentationPage({super.key, required this.noteId});
  final String noteId;

  @override
  ConsumerState<NotePresentationPage> createState() =>
      _NotePresentationPageState();
}

class _NotePresentationPageState extends ConsumerState<NotePresentationPage> {
  final _description = TextEditingController();
  NotePresentationMode? _mode;
  Future<String?>? _preview;
  String? _previewFor;
  bool _showSaved = false;

  static const _ideas = [
    'Clean personal page',
    'Bold landing page',
    'Recipe card',
    'Event invitation',
    'Travel itinerary',
  ];

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _error(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is StateError
            ? error.message.toString()
            : 'Could not change this note.',
      ),
    ),
  );

  Future<void> _removeWebsite() async {
    try {
      ref.read(notesRepositoryProvider).clearWebsite(widget.noteId);
      setState(() => _showSaved = false);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _useMarkdown() async {
    final controller = ref.read(noteSummaryProvider.notifier);
    if (!await controller.acceptTransformation()) return;
    try {
      ref
          .read(notesRepositoryProvider)
          .setPresentationMode(widget.noteId, 'markdown');
    } catch (error) {
      if (mounted) _error(error);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final note = ref
        .watch(notesStreamProvider)
        .value
        ?.where((n) => n.uuid == widget.noteId)
        .firstOrNull;
    final saved =
        note ?? ref.read(notesRepositoryProvider).getNoteByUuid(widget.noteId);
    final state = ref.watch(noteSummaryProvider);
    final handle = state.handle;
    final websiteTask =
        handle?.isNoteWebsite == true && handle!.noteId == widget.noteId;
    final markdownTask =
        handle?.operation == _markdownOperation &&
        handle!.noteId == widget.noteId;
    final mode =
        _mode ??
        (markdownTask || saved?.presentationMode == 'markdown'
            ? NotePresentationMode.markdown
            : NotePresentationMode.website);
    final readOnly =
        ref.watch(syncDeviceRoleProvider) == SyncDeviceRole.secondary;
    final busyElsewhere = handle != null && !websiteTask && !markdownTask;
    return Scaffold(
      appBar: AppBar(title: const Text('Presentation')),
      body: ListView(
        key: const ValueKey('note-presentation'),
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<NotePresentationMode>(
            key: const ValueKey('note-presentation-mode'),
            segments: const [
              ButtonSegment(
                value: NotePresentationMode.website,
                icon: Icon(Icons.web_outlined),
                label: Text('Website'),
              ),
              ButtonSegment(
                value: NotePresentationMode.markdown,
                icon: Icon(Icons.notes_rounded),
                label: Text('Markdown'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: state.busy
                ? null
                : (value) => setState(() => _mode = value.single),
          ),
          const SizedBox(height: 16),
          if (saved == null)
            const Text('This note is no longer available.')
          else if (readOnly)
            const Text(
              'Existing notes are read-only on this device, so their presentation cannot change here.',
            )
          else if (busyElsewhere) ...[
            const Text('Another AI preview is open. Finish or clear it first.'),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NoteSummaryPage(),
                ),
              ),
              child: const Text('Open the current preview'),
            ),
          ] else if (mode == NotePresentationMode.website)
            ..._website(saved, state, websiteTask)
          else
            ..._markdown(state, markdownTask),
        ],
      ),
    );
  }

  List<Widget> _website(NoteEntity note, NoteSummaryState state, bool mine) {
    final controller = ref.read(noteSummaryProvider.notifier);
    final theme = Theme.of(context);
    final hasSite = note.website.isNotEmpty;
    final stale =
        hasSite && websiteContentHash(note.content) != note.websiteSourceHash;
    if (mine && state.phase == 'completed' && _previewFor != state.text) {
      _previewFor = state.text;
      _preview = controller.noteWebsitePreview();
    }
    return [
      if (hasSite && !mine) ...[
        Text('This note has a website', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          stale
              ? 'Your text changed since this website was made. Generate it again to include the changes.'
              : 'It is shown when you open the note. Your text is kept as written.',
          key: stale ? const ValueKey('note-website-stale') : null,
        ),
        if (_showSaved)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 360,
              child: NoteWebsiteView(html: note.website),
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => setState(() => _showSaved = !_showSaved),
              child: Text(_showSaved ? 'Hide preview' : 'Preview'),
            ),
            TextButton(
              key: const ValueKey('note-website-remove'),
              onPressed: _removeWebsite,
              child: const Text('Remove website'),
            ),
          ],
        ),
        const Divider(height: 32),
      ],
      if (!mine) ...[
        TextField(
          key: const ValueKey('note-website-description'),
          controller: _description,
          maxLength: noteWebsiteDescriptionChars,
          decoration: const InputDecoration(
            labelText: 'Describe your website',
            hintText: 'A calm one-page site with soft green cards',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final idea in _ideas)
              ActionChip(
                label: Text(idea),
                onPressed: () => setState(() => _description.text = idea),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_websiteModel() case final model?)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Built on your computer with $model.',
              key: const ValueKey('note-website-model'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        Text(
          'Only this note’s title and text and your description go to your trusted computer. The page is shown with scripts and internet access off.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('note-website-generate'),
          onPressed: state.busy || _description.text.trim().isEmpty
              ? null
              : () => controller.startNoteWebsite(
                  widget.noteId,
                  _description.text,
                ),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(hasSite ? 'Generate a new website' : 'Generate website'),
        ),
      ],
      if (mine) ...[
        Text(
          summaryPhaseLabel(state.phase),
          style: theme.textTheme.titleMedium,
        ),
        if (state.phase == 'completed')
          FutureBuilder<String?>(
            future: _preview,
            builder: (context, snapshot) {
              final html = snapshot.data;
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                );
              }
              if (html == null) {
                return const Text(
                  'The website could not be shown safely. Discard it and try again.',
                  key: ValueKey('note-website-invalid'),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 420, child: NoteWebsiteView(html: html)),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('note-website-use'),
                      onPressed: state.busy || state.stale
                          ? null
                          : () async {
                              final saved = await controller
                                  .acceptNoteWebsite();
                              if (saved && mounted) {
                                Navigator.of(this.context).pop(true);
                              }
                            },
                      child: const Text('Use website'),
                    ),
                  ],
                ),
              );
            },
          ),
        if (state.stale)
          const Text(
            'The note changed while this was being made, so it cannot be saved. Discard it and generate again.',
          ),
        ..._taskControls(state),
      ],
    ];
  }

  /// The model the computer builds websites with, as it reports it.
  String? _websiteModel() {
    final status = ref.watch(
      companionControllerProvider.select((state) => state.status),
    );
    final text = (status?['capabilities'] as List? ?? const [])
        .whereType<Map>()
        .where((c) => c['id'] == 'text')
        .firstOrNull;
    final name = text?['websiteModel'];
    return name is String && name.trim().isNotEmpty && name.length <= 80
        ? name.trim()
        : null;
  }

  List<Widget> _markdown(NoteSummaryState state, bool mine) {
    final controller = ref.read(noteSummaryProvider.notifier);
    final theme = Theme.of(context);
    return [
      const Text(
        'Rewrites this note as Markdown, with headings and lists where they help, and replaces its text. The current text is kept in Prior content / recovery. Any website is removed.',
      ),
      const SizedBox(height: 12),
      if (!mine)
        FilledButton.icon(
          key: const ValueKey('note-markdown-start'),
          onPressed: state.busy
              ? null
              : () => controller.start(
                  widget.noteId,
                  operation: _markdownOperation,
                ),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Format as Markdown'),
        )
      else ...[
        Text(
          summaryPhaseLabel(state.phase),
          style: theme.textTheme.titleMedium,
        ),
        if (state.phase == 'completed' && state.text != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: MarkdownBody(
              key: const ValueKey('note-markdown-preview'),
              data: state.text!,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('note-markdown-use'),
            onPressed: state.busy || state.stale ? null : _useMarkdown,
            child: const Text('Use Markdown'),
          ),
        ],
        ..._taskControls(state),
      ],
    ];
  }

  List<Widget> _taskControls(NoteSummaryState state) {
    final controller = ref.read(noteSummaryProvider.notifier);
    return [
      if (state.busy) const LinearProgressIndicator(),
      if (state.message != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            state.message!,
            key: const ValueKey('note-presentation-message'),
          ),
        ),
      if (state.terminal)
        TextButton(
          key: const ValueKey('note-presentation-discard'),
          onPressed: state.busy ? null : controller.clear,
          child: const Text('Discard'),
        )
      else if (!state.busy)
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
    ];
  }
}
