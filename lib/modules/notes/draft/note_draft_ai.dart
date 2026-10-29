import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:uuid/uuid.dart';

import '../../local_ai/core/ai_router.dart';
import '../images/note_background_gen.dart';
import '../images/note_image_contract.dart';
import '../images/note_scan.dart';
import '../metadata/note_help_contract.dart';
import '../summary/summary_controller.dart';

/// The QVAC tools a new, unsaved note can use.
enum NoteDraftTool { template, scan, background }

class NoteDraftAiState {
  const NoteDraftAiState({
    this.tool,
    this.phase = 'idle',
    this.message,
    this.text,
    this.preview,
    this.page,
  });
  final NoteDraftTool? tool;

  /// The scanned page copy, kept so the sheet can close and reopen.
  final String? page;

  /// idle, submitting, queued, running, completed or failed.
  final String phase;
  final String? message, text;

  /// A generated background, held as a preview until the note adopts it.
  final File? preview;

  bool get busy => const ['submitting', 'queued', 'running'].contains(phase);
  bool get completed => phase == 'completed';

  NoteTemplate? get template => tool == NoteDraftTool.template && text != null
      ? NoteTemplate.parse(text!)
      : null;
  NoteScanResult? get scan => tool == NoteDraftTool.scan && text != null
      ? NoteScanResult.parse(text!)
      : null;
}

/// Runs one QVAC task for an unsaved note, held only in memory.
///
/// Unlike [NoteSummaryController], nothing is persisted, restored or written
/// to a note: results go back to the editor's draft. The editor watches this
/// provider, so closing the editor cancels or acknowledges any task and
/// deletes its preview.
final noteDraftAiProvider =
    NotifierProvider.autoDispose<NoteDraftAiController, NoteDraftAiState>(
      NoteDraftAiController.new,
    );

class NoteDraftAiController extends Notifier<NoteDraftAiState> {
  ({String id, String operation, AiJobProvider computer, int expires})? _job;
  Timer? _poll;
  int _generation = 0;

  late AiJobClient _client;

  // Disposal may not read [state] or [ref], so the last state is mirrored.
  NoteDraftAiState _last = const NoteDraftAiState();

  @override
  NoteDraftAiState build() {
    _client = ref.read(aiJobClientProvider);
    listenSelf((_, next) => _last = next);
    ref.onDispose(() {
      _generation++;
      _poll?.cancel();
      _release(_last);
    });
    return const NoteDraftAiState();
  }

  bool _alive(int generation) => ref.mounted && generation == _generation;

  /// A starting skeleton for what the note is [topic] for.
  Future<void> template(String topic) =>
      _start(NoteDraftTool.template, () async {
        final input = NoteTemplateSource(topic).request();
        return (
          input: input,
          image: null,
          computer: capableProvider(
            ref,
            contractKey: 'noteHelpContract',
            contract: noteHelpContract,
            operation: noteTemplateOperation,
            fallback: 'You can still start the note yourself.',
            update: 'Update the companion to draft templates.',
          ),
        );
      });

  /// Reads the text of an app-owned page copy at [path].
  Future<void> scan(String path) => _start(NoteDraftTool.scan, () async {
    if (!await ref.read(noteScanStoreProvider).owns(path)) {
      throw const CompanionFailure(
        'INVALID_IMAGE',
        'Take or choose the page again.',
      );
    }
    final computer = capableProvider(
      ref,
      capabilityId: 'vision',
      contractKey: 'scanContract',
      contract: noteScanContract,
      operation: noteScanOperation,
      fallback: 'Your note is unchanged.',
      update: 'Update the companion to scan pages.',
      notReady:
          'Download Qwen3-VL and run the image self-test on your computer.',
      notReadyCode: 'VISION_NOT_READY',
    );
    final image = await prepareNoteImage(
      NoteAttachment(path: path, type: 'image/*'),
    );
    return (input: noteScanPrompt, image: image, computer: computer);
  }, page: path);

  /// Generates a background from [prompt]; only it and [tone] are sent.
  Future<void> background(String prompt, String tone) =>
      _start(NoteDraftTool.background, () async {
        final input = NoteBackgroundRequest(
          noteId: '',
          prompt: prompt,
          tone: tone,
          background: const {},
        ).request();
        return (
          input: input,
          image: null,
          computer: capableProvider(
            ref,
            capabilityId: 'image',
            contractKey: 'backgroundContract',
            contract: noteBackgroundContract,
            operation: noteBackgroundOperation,
            fallback: 'You can still choose a color or photo background.',
            update: 'Update the companion to generate backgrounds.',
            notReady:
                'Download, assign and test an image model on your computer.',
            notReadyCode: 'IMAGE_NOT_READY',
          ),
        );
      });

  /// Drops the current task or result so the tool can start again.
  void reset() {
    _generation++;
    _poll?.cancel();
    _release(state);
    state = const NoteDraftAiState();
  }

  Future<void> _start(
    NoteDraftTool tool,
    Future<({String input, Uint8List? image, AiJobProvider computer})>
    Function()
    prepare, {
    String? page,
  }) async {
    if (state.busy) return;
    _poll?.cancel();
    _release(state);
    final generation = ++_generation;
    state = NoteDraftAiState(tool: tool, phase: 'submitting', page: page);
    try {
      final (:input, :image, :computer) = await prepare();
      if (!_alive(generation)) return;
      final operation = switch (tool) {
        NoteDraftTool.template => noteTemplateOperation,
        NoteDraftTool.scan => noteScanOperation,
        NoteDraftTool.background => noteBackgroundOperation,
      };
      final job = (
        id: const Uuid().v4(),
        operation: operation,
        computer: computer,
        expires:
            DateTime.now().millisecondsSinceEpoch +
            const Duration(hours: 24).inMilliseconds,
      );
      _job = job;
      final response = await _client.authenticated(
        computer,
        'POST',
        image == null ? '/v1/jobs' : '/v1/image-jobs',
        body: {
          'id': job.id,
          'operation': operation,
          'prompt': input,
          'expires': job.expires,
          if (image != null) 'image': base64Encode(image),
        },
      );
      if (!_alive(generation)) return;
      await _consume(response, generation);
    } catch (error) {
      if (_alive(generation)) _fail(error);
    }
  }

  Future<void> _check(int generation) async {
    final job = _job;
    if (job == null || !_alive(generation)) return;
    try {
      final response = await _client.authenticated(
        job.computer,
        'GET',
        '/v1/jobs/${job.id}',
      );
      if (!_alive(generation)) return;
      await _consume(response, generation);
    } on CompanionFailure catch (error) {
      if (!_alive(generation)) return;
      // A missed poll is not an answer: keep waiting until the task expires.
      if (error.code == 'UNAVAILABLE' &&
          DateTime.now().millisecondsSinceEpoch < job.expires) {
        state = NoteDraftAiState(
          tool: state.tool,
          page: state.page,
          phase: state.phase,
          message: 'Waiting for your computer…',
        );
        _poll = Timer(const Duration(seconds: 5), () => _check(generation));
      } else {
        _fail(error);
      }
    } catch (error) {
      if (_alive(generation)) _fail(error);
    }
  }

  Future<void> _consume(Map<String, dynamic> response, int generation) async {
    final job = _job!;
    final phase = response['state'];
    if (response['id'] != job.id ||
        response['device'] != job.computer.deviceId ||
        response['operation'] != job.operation ||
        response['model'] is! String ||
        phase is! String) {
      throw const CompanionFailure(
        'INVALID_RESPONSE',
        'The computer returned an invalid task. Update both apps and retry.',
      );
    }
    switch (phase) {
      case 'queued' || 'running':
        final progress = switch (response['progress']) {
          {'step': final int step, 'total': final int total} =>
            'Step $step of $total',
          _ => null,
        };
        state = NoteDraftAiState(
          tool: state.tool,
          page: state.page,
          phase: phase,
          message: progress,
        );
        _poll = Timer(const Duration(seconds: 3), () => _check(generation));
      case 'completed':
        final text = response['text'];
        final tool = state.tool!;
        if (text is! String ||
            !validSummaryText(text, switch (tool) {
              NoteDraftTool.template => noteTemplateOutputBytes,
              NoteDraftTool.scan => noteScanOutputBytes,
              NoteDraftTool.background => 1024,
            })) {
          throw const CompanionFailure(
            'INVALID_OUTPUT',
            'The computer returned an empty or invalid result.',
          );
        }
        final clean = text.trim();
        File? preview;
        try {
          switch (tool) {
            case NoteDraftTool.template:
              NoteTemplate.parse(clean);
            case NoteDraftTool.scan:
              NoteScanResult.parse(clean);
            case NoteDraftTool.background:
              preview = await _collectBackground(job, clean);
          }
        } on FormatException {
          throw const CompanionFailure(
            'INVALID_OUTPUT',
            'The computer returned an empty or invalid result.',
          );
        }
        if (!_alive(generation)) {
          if (preview != null) unawaited(_deleteQuietly(preview));
          return;
        }
        // Nothing here is retried later, so the computer can let it go now.
        _acknowledge(job);
        _job = null;
        state = NoteDraftAiState(
          tool: tool,
          page: state.page,
          phase: 'completed',
          text: clean,
          preview: preview,
        );
      default:
        _job = null;
        state = NoteDraftAiState(
          tool: state.tool,
          page: state.page,
          phase: 'failed',
          message: switch (phase) {
            'cancelled' => 'Cancelled. Nothing was added to your note.',
            'expired' => 'The task expired on your computer. Try again.',
            'interrupted' =>
              'Your computer stopped before finishing. Try again.',
            _ =>
              response['error'] == 'OUTPUT_LIMIT'
                  ? 'The result was too long. Try a shorter description.'
                  : 'Your computer could not finish. Check its model and try again.',
          },
        );
    }
  }

  Future<File> _collectBackground(
    ({String id, String operation, AiJobProvider computer, int expires}) job,
    String text,
  ) async {
    final result = NoteBackgroundResult.parse(text);
    final response = await _client.authenticated(
      job.computer,
      'GET',
      '/v1/image-jobs/${job.id}/result',
    );
    final image = response['image'];
    final bytes = image is String ? base64Decode(image) : Uint8List(0);
    if (response['id'] != job.id ||
        !result.matches(bytes, await hexHash(bytes))) {
      throw const CompanionFailure(
        'INVALID_OUTPUT',
        'The computer returned a different image than it described.',
      );
    }
    final store = ref.read(noteBackgroundStoreProvider);
    await store.savePreview(job.id, bytes);
    return store.preview(job.id);
  }

  void _fail(Object error) {
    _poll?.cancel();
    final job = _job;
    _job = null;
    if (job != null) _cancel(job);
    state = NoteDraftAiState(
      tool: state.tool,
      page: state.page,
      phase: 'failed',
      message: switch (error) {
        CompanionFailure(code: 'NOT_READY') =>
          'Load and assign the writing model on your computer, then try again.',
        CompanionFailure(:final message) => message,
        FormatException(:final message) => message,
        _ => 'Something went wrong. Nothing was added to your note.',
      },
    );
  }

  /// Best effort only: the draft keeps no record to retry from.
  void _release(NoteDraftAiState current) {
    final job = _job;
    _job = null;
    if (job != null && current.busy) _cancel(job);
    if (current.preview case final preview?) _deleteSync(preview);
  }

  void _cancel(
    ({String id, String operation, AiJobProvider computer, int expires}) job,
  ) => unawaited(
    _client
        .authenticated(
          job.computer,
          'POST',
          '/v1/jobs/${job.id}/cancel',
          body: {'operation': job.operation},
        )
        .then((_) {}, onError: (Object _) {}),
  );

  void _acknowledge(
    ({String id, String operation, AiJobProvider computer, int expires}) job,
  ) => unawaited(
    _client
        .authenticated(job.computer, 'POST', '/v1/jobs/${job.id}/ack', body: {})
        .then((_) {}, onError: (Object _) {}),
  );

  // Runs from disposal, where nothing can wait for a future.
  static void _deleteSync(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
