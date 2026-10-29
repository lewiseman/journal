import 'package:journal/modules/notes/views/widgets/note_ai_loading.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

import '../summary/summary_controller.dart';
import '../summary/summary_history_page.dart';
import '../summary/summary_page.dart';
import 'note_scan.dart';

/// Returns a picked page's temporary path, or null when cancelled.
final noteScanPickerProvider =
    Provider<Future<String?> Function(ImageSource source)>(
      (ref) =>
          (source) async => (await ImagePicker().pickImage(
            source: source,
            maxWidth: 2400,
            maxHeight: 2400,
            imageQuality: 92,
            requestFullMetadata: false,
          ))?.path,
    );

class NoteScanPage extends ConsumerStatefulWidget {
  const NoteScanPage({super.key, required this.noteId});
  final String noteId;
  @override
  ConsumerState<NoteScanPage> createState() => _NoteScanPageState();
}

class _NoteScanPageState extends ConsumerState<NoteScanPage> {
  final _text = TextEditingController();
  String? _scan, _shownFor, _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    // Picked pages never read or inserted are removed after a day.
    final handle = ref.read(noteSummaryProvider).handle;
    final active = handle?.isNoteScan == true && handle!.localSource != null
        ? {NoteScanRequest.decode(handle.localSource!).path}
        : <String>{};
    ref
        .read(noteScanStoreProvider)
        .sweep(
          ref.read(notesRepositoryProvider).allAttachmentPaths(),
          keep: active,
        )
        .catchError((Object _) {});
  }

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
    final store = ref.read(noteScanStoreProvider);
    try {
      final picked = await ref.read(noteScanPickerProvider)(source);
      if (picked == null || !mounted) return;
      final copy = await store.import(picked);
      if (_scan != null) await store.delete(_scan!);
      if (mounted) setState(() => _scan = copy);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code.contains('access_denied')
              ? 'Allow camera or photo access for Journal in system Settings, or choose another source.'
              : 'Could not open the camera or photos. Try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not keep a copy of that image. Check free space and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _rotate() async {
    setState(() => _working = true);
    try {
      final rotated = await ref.read(noteScanStoreProvider).rotate(_scan!);
      if (mounted) setState(() => _scan = rotated);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not rotate this image.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Clears the finished task; keeps the picked page for another attempt.
  Future<void> _again(String path) async {
    await ref.read(noteSummaryProvider.notifier).clear();
    if (mounted) setState(() => _scan = path);
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
    final mine = handle?.isNoteScan == true;
    final request = mine && handle!.localSource != null
        ? NoteScanRequest.decode(handle.localSource!)
        : null;
    final readOnly =
        ref.watch(syncDeviceRoleProvider) == SyncDeviceRole.secondary;
    final result = mine ? controller.noteScanResult() : null;
    if (result != null && _shownFor != handle!.id) {
      _shownFor = handle.id;
      _text.text = result.text;
    }
    final theme = Theme.of(context).textTheme;
    final page = request?.path ?? _scan;
    final previous = [
      for (final entry
          in ref
                  .watch(notesRepositoryProvider)
                  .getNoteByUuid(widget.noteId)
                  ?.attachments ??
              const <Map<String, dynamic>>[])
        if (NoteAttachment.tryFromMap(entry) case final a?
            when a.path.contains('/note_scans/'))
          a,
    ];
    return NoteAiScaffold(
      tool: NoteAiTool.scan,
      loading:
          (handle == null || (mine && handle.noteId == widget.noteId)) &&
              noteAiIsLoading(state.phase, busy: state.busy)
          ? NoteAiLoading(
              tool: NoteAiTool.scan,
              phase: state.phase,
              onCancel: handle != null && !state.busy && !state.terminal
                  ? controller.cancel
                  : null,
            )
          : null,
      step: result != null
          ? 2
          : state.busy
          ? 1
          : 0,
      children: [
        const NoteAiDetails(
          'Photograph or choose a page of printed or handwritten notes. The text is read on your trusted computer and shown here to correct before anything is added. Handwriting, unusual layouts and languages other than English are read less reliably: check every line.',
          title: 'Tips for a good scan',
        ),
        const SizedBox(height: 12),
        if (readOnly)
          const Text(
            'Existing notes are read-only on this device, so scans cannot be added here.',
          ),
        if (page != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(page),
                key: ValueKey(page),
                height: 260,
                fit: BoxFit.contain,
                cacheHeight: 780,
                errorBuilder: (_, _, _) =>
                    const Text('This page image is no longer available.'),
              ),
            ),
          ),
        if (handle == null && state.phase == 'idle' && !readOnly) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('note-scan-camera'),
                onPressed: _working ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(_scan == null ? 'Take photo' : 'Retake'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('note-scan-gallery'),
                onPressed: _working ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose image'),
              ),
              if (_scan != null)
                OutlinedButton.icon(
                  onPressed: _working ? null : _rotate,
                  icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                  label: const Text('Rotate'),
                ),
            ],
          ),
          const SizedBox(height: 8),

          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('note-scan-start'),
            onPressed: _scan == null || _working
                ? null
                : () => controller.startNoteScan(widget.noteId, path: _scan!),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Read text'),
          ),
        ],
        if (_error != null)
          Text(_error!, key: const ValueKey('note-scan-error')),
        if (handle != null && !mine) ...[
          const Text('Another AI preview is open. Finish or clear it first.'),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NoteSummaryPage()),
            ),
            child: const Text('Open the current preview'),
          ),
        ],
        if (mine) ...[
          Text(summaryPhaseLabel(state.phase), style: theme.titleMedium),
          if (state.stale)
            const Text(
              'The note changed or the page image is gone. This text cannot be inserted.',
              key: ValueKey('note-scan-stale'),
            ),
          if (state.text != null && result == null)
            const Text('The transcription could not be read safely.'),
          if (result != null && (result.empty || !result.readable)) ...[
            const Text(
              'No legible text was found. Try a sharper, brighter photo with the page upright, or rotate it.',
              key: ValueKey('note-scan-unreadable'),
            ),
            if (request != null)
              TextButton(
                onPressed: () => _again(request.path),
                child: const Text('Try again with this page'),
              ),
          ],
          if (result != null && !result.empty) ...[
            const SizedBox(height: 8),
            NoteScanReview(
              result: result,
              controller: _text,
              onChanged: () => setState(() {}),
            ),
            FilledButton(
              key: const ValueKey('note-scan-insert'),
              onPressed:
                  state.stale ||
                      state.busy ||
                      readOnly ||
                      _text.text.trim().isEmpty
                  ? null
                  : () async {
                      final inserted = await controller.acceptNoteScan(
                        _text.text,
                      );
                      if (inserted && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
              child: const Text('Insert text and attach page'),
            ),
          ],
          if (state.terminal)
            TextButton(
              onPressed: state.busy
                  ? null
                  : () async {
                      final path = request?.path;
                      await controller.clear();
                      if (path != null) {
                        await ref.read(noteScanStoreProvider).delete(path);
                      }
                      if (mounted) setState(() => _scan = null);
                    },
              child: const Text('Discard scan'),
            ),
          if (!state.terminal && !state.busy)
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
        ],
        if (state.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              state.message!,
              key: const ValueKey('note-scan-message'),
            ),
          ),
        if (handle == null && state.phase != 'idle' && !state.busy)
          TextButton(
            onPressed: state.phase == 'storageError'
                ? controller.restore
                : controller.clear,
            child: const Text('Return'),
          ),
        if (previous.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Earlier scans of this note', style: theme.titleSmall),
          for (final scan in previous)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(scan.filename, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.notes_outlined),
              onTap: () async {
                final original = await ref
                    .read(noteScanStoreProvider)
                    .readOriginal(scan.path);
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Original transcription'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        original ?? 'No original transcription is kept for this page on this phone.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ],
    );
  }
}

/// The reviewed transcription: how far to trust it, and the text to insert.
class NoteScanReview extends StatelessWidget {
  const NoteScanReview({
    super.key,
    required this.result,
    required this.controller,
    this.onChanged,
  });
  final NoteScanResult result;
  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        result.check == null
            ? 'Not cross-checked: no second reader is installed on your computer. Check names, dates and numbers yourself.'
            : result.disagreements.isEmpty
            ? 'A second reader agreed on names, dates and numbers. Still check the text.'
            : 'Check these: a second reader read them differently.',
        key: const ValueKey('note-scan-check-summary'),
      ),
      if (result.disagreements.isNotEmpty)
        Wrap(
          spacing: 6,
          children: [
            for (final word in result.disagreements)
              Chip(
                avatar: const Icon(Icons.help_outline, size: 16),
                label: Text(word),
              ),
          ],
        ),
      if (result.unreadableMarks > 0)
        Text(
          '${result.unreadableMarks} place${result.unreadableMarks == 1 ? '' : 's'} marked [?] could not be read. Replace them with what the page says.',
          key: const ValueKey('note-scan-marks'),
        ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('note-scan-text'),
        controller: controller,
        minLines: 4,
        maxLines: 14,
        decoration: const InputDecoration(
          labelText: 'Text to insert (edit freely)',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => onChanged?.call(),
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Original transcription'),
        children: [SelectableText(result.text)],
      ),
    ],
  );
}
