import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../images/note_background_gen.dart';
import '../images/note_scan.dart';
import '../images/note_scan_page.dart';
import '../metadata/note_help_contract.dart';
import 'note_draft_ai.dart';

/// What a draft tool hands back to the editor. Nothing is saved until the
/// note is.
sealed class NoteDraftResult {
  const NoteDraftResult();
}

class DraftTemplateResult extends NoteDraftResult {
  const DraftTemplateResult(this.template);
  final NoteTemplate template;
}

class DraftScanResult extends NoteDraftResult {
  const DraftScanResult({
    required this.text,
    required this.path,
    required this.original,
  });

  /// The reviewed text, the app-owned page copy and the unedited reading.
  final String text, path, original;
}

class DraftBackgroundResult extends NoteDraftResult {
  const DraftBackgroundResult(this.image);

  /// A permanent app-owned copy of the generated image.
  final String image;
}

/// A new note's starting skeleton, from one line about what it is for.
class NoteDraftTemplatePage extends ConsumerStatefulWidget {
  const NoteDraftTemplatePage({super.key, this.topic = ''});
  final String topic;

  @override
  ConsumerState<NoteDraftTemplatePage> createState() =>
      _NoteDraftTemplatePageState();
}

class _NoteDraftTemplatePageState extends ConsumerState<NoteDraftTemplatePage> {
  late final _topic = TextEditingController(text: widget.topic.trim());

  static const _suggestions = [
    'Meeting notes',
    'Trip plan',
    'Recipe',
    'Weekly review',
    'Book notes',
  ];

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noteDraftAiProvider);
    final controller = ref.read(noteDraftAiProvider.notifier);
    final mine = state.tool == NoteDraftTool.template;
    final template = mine ? state.template : null;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _DraftScaffold(
      title: 'Starting template',
      tool: NoteDraftTool.template,
      children: [
        if (template == null) ...[
          TextField(
            key: const ValueKey('note-draft-template-topic'),
            controller: _topic,
            enabled: !state.busy,
            maxLength: noteIdeaTopicChars,
            textInputAction: TextInputAction.go,
            decoration: const InputDecoration(
              labelText: 'What’s this note for?',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) controller.template(value);
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final suggestion in _suggestions)
                ActionChip(
                  avatar: Icon(switch (suggestion) {
                    'Meeting notes' => Icons.groups_outlined,
                    'Trip plan' => Icons.map_outlined,
                    'Recipe' => Icons.restaurant_outlined,
                    'Weekly review' => Icons.date_range_outlined,
                    _ => Icons.menu_book_outlined,
                  }, size: 19),
                  label: Text(suggestion),
                  onPressed: state.busy
                      ? null
                      : () => setState(() => _topic.text = suggestion),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('note-draft-template-start'),
            onPressed: state.busy || _topic.text.trim().isEmpty
                ? null
                : () => controller.template(_topic.text),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Draft a template'),
          ),
        ] else ...[
          Container(
            key: const ValueKey('note-draft-template-preview'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(template.body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('note-draft-template-use'),
            onPressed: () {
              controller.reset();
              Navigator.of(context).pop(DraftTemplateResult(template));
            },
            child: const Text('Use template'),
          ),
          TextButton(
            onPressed: () => controller.template(_topic.text),
            child: const Text('Try another'),
          ),
        ],
      ],
    );
  }
}

/// Reads a photographed page into a new note, after the person checks it.
class NoteDraftScanPage extends ConsumerStatefulWidget {
  const NoteDraftScanPage({super.key});

  @override
  ConsumerState<NoteDraftScanPage> createState() => _NoteDraftScanPageState();
}

class _NoteDraftScanPageState extends ConsumerState<NoteDraftScanPage> {
  final _text = TextEditingController();
  String? _page, _shown, _error;
  bool _working = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final picked = await ref.read(noteScanPickerProvider)(source);
      if (picked == null || !mounted) return;
      final copy = await ref.read(noteScanStoreProvider).import(picked);
      if (mounted) setState(() => _page = copy);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code.contains('access_denied')
              ? 'Allow camera or photo access for Journal in system Settings.'
              : 'Could not open the camera or photos. Try again.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not keep that image.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _rotate(String page) async {
    setState(() => _working = true);
    try {
      final rotated = await ref.read(noteScanStoreProvider).rotate(page);
      if (mounted) setState(() => _page = rotated);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not rotate this image.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noteDraftAiProvider);
    final controller = ref.read(noteDraftAiProvider.notifier);
    final mine = state.tool == NoteDraftTool.scan;
    final page = (mine ? state.page : null) ?? _page;
    NoteScanResult? result;
    try {
      result = mine ? state.scan : null;
    } on FormatException {
      result = null;
    }
    if (result != null && _shown != state.text) {
      _shown = state.text;
      _text.text = result.text;
    }
    final readable = result != null && !result.empty && result.readable;
    return _DraftScaffold(
      title: 'Scan a page',
      tool: NoteDraftTool.scan,
      children: [
        if (page != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(page),
                key: ValueKey(page),
                height: readable ? 160 : 260,
                fit: BoxFit.contain,
                cacheHeight: 780,
                errorBuilder: (_, _, _) =>
                    const Text('This page image is no longer available.'),
              ),
            ),
          ),
        if (result == null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('note-draft-scan-camera'),
                onPressed: _working || state.busy
                    ? null
                    : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(page == null ? 'Take photo' : 'Retake'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('note-draft-scan-gallery'),
                onPressed: _working || state.busy
                    ? null
                    : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose image'),
              ),
              if (page != null)
                OutlinedButton.icon(
                  onPressed: _working || state.busy
                      ? null
                      : () => _rotate(page),
                  icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                  label: const Text('Rotate'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('note-draft-scan-start'),
            onPressed: page == null || _working || state.busy
                ? null
                : () => controller.scan(page),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Read text'),
          ),
        ] else if (!readable) ...[
          const Text(
            'No legible text was found. Try a sharper, brighter photo with the page upright.',
            key: ValueKey('note-draft-scan-unreadable'),
          ),
          TextButton(
            onPressed: () {
              controller.reset();
              setState(() => _page = page);
            },
            child: const Text('Try again'),
          ),
        ] else ...[
          NoteScanReview(
            result: result,
            controller: _text,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('note-draft-scan-insert'),
            onPressed: _text.text.trim().isEmpty
                ? null
                : () {
                    final scan = DraftScanResult(
                      text: _text.text.trim(),
                      path: page!,
                      original: result!.text,
                    );
                    controller.reset();
                    Navigator.of(context).pop(scan);
                  },
            child: const Text('Add to note'),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, key: const ValueKey('note-draft-scan-error')),
          ),
      ],
    );
  }
}

/// Generates a background for a new note from one line of description.
class NoteDraftBackgroundPage extends ConsumerStatefulWidget {
  const NoteDraftBackgroundPage({super.key});

  @override
  ConsumerState<NoteDraftBackgroundPage> createState() =>
      _NoteDraftBackgroundPageState();
}

class _NoteDraftBackgroundPageState
    extends ConsumerState<NoteDraftBackgroundPage> {
  final _prompt = TextEditingController();
  String _tone = 'light';
  bool _adopting = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _use(File preview) async {
    setState(() => _adopting = true);
    try {
      final image = await ref
          .read(noteBackgroundStoreProvider)
          .adopt(p.basenameWithoutExtension(preview.path));
      if (!mounted) return;
      ref.read(noteDraftAiProvider.notifier).reset();
      Navigator.of(context).pop(DraftBackgroundResult(image));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not keep this background.')),
        );
      }
    } finally {
      if (mounted) setState(() => _adopting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noteDraftAiProvider);
    final controller = ref.read(noteDraftAiProvider.notifier);
    final preview = state.tool == NoteDraftTool.background
        ? state.preview
        : null;
    return _DraftScaffold(
      title: 'Generate a background',
      tool: NoteDraftTool.background,
      children: [
        if (preview == null) ...[
          NoteAiBackdropIdeas(
            value: _prompt.text,
            onChanged: state.busy
                ? null
                : (value) => setState(() => _prompt.text = value),
          ),
          TextField(
            key: const ValueKey('note-draft-background-prompt'),
            controller: _prompt,
            enabled: !state.busy,
            maxLength: noteBackgroundPromptChars,
            decoration: const InputDecoration(
              labelText: 'Describe the background',
              hintText: 'Sea glass and morning fog',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          NoteAiChoices<String>(
            choices: noteBackgroundTones,
            selected: _tone,
            icons: const {
              'light': Icons.light_mode_outlined,
              'dark': Icons.dark_mode_outlined,
            },
            onChanged: state.busy
                ? null
                : (value) => setState(() => _tone = value),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('note-draft-background-start'),
            onPressed: state.busy || _prompt.text.trim().isEmpty
                ? null
                : () => controller.background(_prompt.text, _tone),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Generate'),
          ),
        ] else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 280,
              child: Image.file(
                preview,
                key: const ValueKey('note-draft-background-preview'),
                fit: BoxFit.cover,
                // The preview is removed once adopted, while this page closes.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('note-draft-background-use'),
            onPressed: _adopting ? null : () => _use(preview),
            child: const Text('Use background'),
          ),
          TextButton(
            onPressed: _adopting
                ? null
                : () => controller.background(_prompt.text, _tone),
            child: const Text('Try another'),
          ),
        ],
      ],
    );
  }
}

/// Shared frame: progress, failures, and a note when another draft tool's
/// task is still running.
class _DraftScaffold extends ConsumerWidget {
  const _DraftScaffold({
    required this.title,
    required this.tool,
    required this.children,
  });
  final String title;
  final NoteDraftTool tool;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noteDraftAiProvider);
    final controller = ref.read(noteDraftAiProvider.notifier);
    final other = state.tool != null && state.tool != tool && state.busy;
    final mine = state.tool == tool;
    return NoteAiScaffold(
      tool: NoteAiTool.values.byName(tool.name),
      step: mine && state.completed
          ? 2
          : mine && state.busy
          ? 1
          : 0,
      children: [
        if (other) ...[
          const Text(
            'Another QVAC task for this note is still running.',
            key: ValueKey('note-draft-other'),
          ),
          TextButton(onPressed: controller.reset, child: const Text('Stop it')),
        ] else ...[
          ...children,
          if (mine && state.busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(key: ValueKey('note-draft-progress')),
            const SizedBox(height: 8),
            Text(state.message ?? 'Working on your computer…'),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('note-draft-cancel'),
                onPressed: controller.reset,
                child: const Text('Cancel'),
              ),
            ),
          ],
          if (mine && state.phase == 'failed' && state.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                state.message!,
                key: const ValueKey('note-draft-message'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ],
    );
  }
}
