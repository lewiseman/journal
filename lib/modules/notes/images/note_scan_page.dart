import 'package:journal/modules/notes/views/widgets/note_ai_loading.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

import '../summary/summary_controller.dart';
import '../summary/summary_page.dart';
import '../summary/summary_store.dart';
import 'note_scan.dart';
import 'note_scan_parts.dart';
import 'note_scan_stage.dart';

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
    final loading =
        (handle == null || (mine && handle.noteId == widget.noteId)) &&
        noteAiIsLoading(state.phase, busy: state.busy);
    final onCancel = handle != null && !state.busy && !state.terminal
        ? controller.cancel
        : null;
    // With the page in hand it stays on screen while it is read.
    final analyzing = loading && page != null;
    final picking = handle == null && state.phase == 'idle' && !readOnly;
    final idle = !_working;
    return NoteScanEntrance(
      child: NoteAiScaffold(
        tool: NoteAiTool.scan,
        header: const SizedBox.shrink(),
        loading: loading && !analyzing
            ? NoteAiLoading(
                tool: NoteAiTool.scan,
                phase: state.phase,
                onCancel: onCancel,
              )
            : null,
        children: [
          if (readOnly) ...[
            const NoteScanCallout('Read-only on this device'),
            const SizedBox(height: 12),
          ],
          NoteScanStage(
            page: page,
            analyzing: analyzing,
            compact: result != null && !result.empty,
            empty: picking
                ? NoteScanEmpty(
                    cameraKey: const ValueKey('note-scan-camera'),
                    galleryKey: const ValueKey('note-scan-gallery'),
                    onCamera: idle ? () => _pick(ImageSource.camera) : null,
                    onGallery: idle ? () => _pick(ImageSource.gallery) : null,
                  )
                : null,
            overlay: analyzing
                ? NoteScanReading(
                    key: const ValueKey('analyzing'),
                    phase: state.phase,
                    onStop: onCancel,
                  )
                : picking && page != null
                ? NoteScanToolbar(
                    key: const ValueKey('tools'),
                    children: [
                      NoteScanTool(
                        key: const ValueKey('note-scan-camera'),
                        icon: Icons.photo_camera_outlined,
                        tooltip: 'Retake',
                        onPressed: idle
                            ? () => _pick(ImageSource.camera)
                            : null,
                      ),
                      NoteScanTool(
                        key: const ValueKey('note-scan-gallery'),
                        icon: Icons.photo_library_outlined,
                        tooltip: 'Choose image',
                        onPressed: idle
                            ? () => _pick(ImageSource.gallery)
                            : null,
                      ),
                      NoteScanTool(
                        icon: Icons.rotate_90_degrees_cw_outlined,
                        tooltip: 'Rotate',
                        onPressed: idle ? _rotate : null,
                      ),
                    ],
                  )
                : null,
          ),
          NoteScanSteps(
            child: Column(
              key: ValueKey(
                analyzing
                    ? 'analyzing'
                    : result != null
                    ? 'result'
                    : handle != null
                    ? 'task'
                    : picking
                    ? 'pick'
                    : 'done',
              ),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: analyzing
                  ? const []
                  : _steps(
                      context,
                      state: state,
                      handle: handle,
                      request: request,
                      result: result,
                      readOnly: readOnly,
                      picking: picking,
                      previous: previous,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _steps(
    BuildContext context, {
    required NoteSummaryState state,
    required SummaryHandle? handle,
    required NoteScanRequest? request,
    required NoteScanResult? result,
    required bool readOnly,
    required bool picking,
    required List<NoteAttachment> previous,
  }) {
    final controller = ref.read(noteSummaryProvider.notifier);
    final theme = Theme.of(context).textTheme;
    final mine = handle?.isNoteScan == true;
    const gap = SizedBox(height: 12);
    return [
      if (picking && _scan != null)
        FilledButton.icon(
          key: const ValueKey('note-scan-start'),
          onPressed: _working
              ? null
              : () => controller.startNoteScan(widget.noteId, path: _scan!),
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Read text'),
        ),
      if (_error != null) ...[
        gap,
        NoteScanCallout(
          _error!,
          key: const ValueKey('note-scan-error'),
          tone: NoteScanTone.error,
        ),
      ],
      if (handle != null && !mine) ...[
        const NoteScanCallout('Another AI preview is open'),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const NoteSummaryPage()),
          ),
          child: const Text('Open the current preview'),
        ),
      ],
      if (mine) ...[
        if (state.stale) ...[
          const NoteScanCallout(
            'The note or page changed, so this text can’t be inserted',
            key: ValueKey('note-scan-stale'),
            tone: NoteScanTone.caution,
          ),
          gap,
        ],
        if (state.text != null && result == null) ...[
          const NoteScanCallout(
            'The text couldn’t be read safely',
            tone: NoteScanTone.error,
          ),
          gap,
        ],
        if (result != null && (result.empty || !result.readable)) ...[
          const NoteScanCallout(
            'No legible text found',
            key: ValueKey('note-scan-unreadable'),
            tone: NoteScanTone.caution,
          ),
          if (request != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                onPressed: () => _again(request.path),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again with this page'),
              ),
            ),
          gap,
        ],
        if (result != null && !result.empty) ...[
          NoteScanReview(
            result: result,
            controller: _text,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
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
            icon: const Icon(Icons.note_add_rounded),
            label: const Text('Insert text and attach page'),
          ),
        ],
        if (state.terminal)
          Center(
            child: TextButton.icon(
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
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: const Text('Discard scan'),
            ),
          ),
        if (!state.terminal && !state.busy)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.retry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Retry / retrieve same task'),
              ),
              TextButton(
                onPressed: controller.cancel,
                child: const Text('Cancel task'),
              ),
            ],
          ),
      ],
      if (state.message != null) ...[
        gap,
        NoteScanCallout(
          state.message!,
          key: const ValueKey('note-scan-message'),
        ),
      ],
      if (handle == null && state.phase != 'idle' && !state.busy)
        TextButton(
          onPressed: state.phase == 'storageError'
              ? controller.restore
              : controller.clear,
          child: const Text('Return'),
        ),
      if (previous.isNotEmpty) ...[
        const SizedBox(height: 28),
        Text('Earlier scans', style: theme.titleSmall),
        const SizedBox(height: 10),
        for (final scan in previous)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: NoteAiTool.scan.ink(context).withValues(alpha: .06),
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(scan.filename, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded),
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
          ),
      ],
    ];
  }
}

/// The read text to correct, with what to double-check as pills on top.
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disagreements = result.disagreements;
    final (_, caution) = noteScanTone(context, NoteScanTone.caution);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NoteScanPill(
              result.check == null
                  ? 'Not cross-checked'
                  : disagreements.isEmpty
                  ? 'Cross-checked'
                  : 'Check ${disagreements.length == 1 ? 'this' : 'these'}',
              key: const ValueKey('note-scan-check-summary'),
              tone: result.check == null
                  ? NoteScanTone.info
                  : disagreements.isEmpty
                  ? NoteScanTone.good
                  : NoteScanTone.caution,
            ),
            for (final word in disagreements)
              Chip(
                label: Text(word),
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: caution.withValues(alpha: .06),
                side: BorderSide(color: caution.withValues(alpha: .4)),
                shape: const StadiumBorder(),
                visualDensity: VisualDensity.compact,
              ),
            if (result.unreadableMarks > 0)
              NoteScanPill(
                '${result.unreadableMarks} unreadable [?]',
                key: const ValueKey('note-scan-marks'),
                tone: NoteScanTone.caution,
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('note-scan-text'),
          controller: controller,
          minLines: 5,
          maxLines: 14,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          decoration: const InputDecoration(contentPadding: EdgeInsets.all(18)),
          onChanged: (_) => onChanged?.call(),
        ),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(Icons.history_rounded, size: 20),
          title: Text('Original', style: theme.textTheme.bodyMedium),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SelectableText(result.text),
            ),
          ],
        ),
      ],
    );
  }
}
