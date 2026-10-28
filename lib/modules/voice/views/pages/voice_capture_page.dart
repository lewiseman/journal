import 'dart:async';

import 'package:journal/common.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/modules/voice/controllers/voice_capture.dart';
import 'package:journal/modules/voice/views/widgets/voice_ambient_background.dart';

class VoiceCapturePage extends ConsumerStatefulWidget {
  const VoiceCapturePage({
    super.key,
    required this.title,
    this.target = 'note',
  });
  final String title, target;
  @override
  ConsumerState<VoiceCapturePage> createState() => _VoiceCapturePageState();
}

class _VoiceCapturePageState extends ConsumerState<VoiceCapturePage>
    with WidgetsBindingObserver {
  late final VoiceCapture _capture;
  final _review = TextEditingController();
  String _lastTranscript = '';
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capture = VoiceCapture(
      target: widget.target,
      computer: () {
        if (ref.read(accountResetProvider).blocksDataAccess) {
          throw const CompanionFailure(
            'RESET',
            'Account reset is in progress.',
          );
        }
        final c = ref.read(companionControllerProvider).selected;
        if (c == null) {
          throw const CompanionFailure(
            'UNAVAILABLE',
            'Pair your computer in Settings → Local AI computer.',
          );
        }
        return c;
      },
    );
    _capture.addListener(_changed);
    unawaited(_capture.restore());
  }

  void _changed() {
    if (!mounted) return;
    if (_capture.text != _lastTranscript) {
      _lastTranscript = _capture.text;
      _review.text = _capture.text;
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _capture.recording) {
      _capture.interruption =
          'Recording paused when the app left the foreground.';
      unawaited(_capture.stop());
    }
  }

  Future<void> _use() async {
    if (_saving ||
        _review.text.trim().isEmpty ||
        _capture.recording ||
        ref.read(accountResetProvider).blocksDataAccess) {
      return;
    }
    setState(() => _saving = true);
    try {
      final text = _review.text.trim();
      // Flow's normal repository owns permissions/outbox; a stable UUID also
      // prevents duplicate creations if the app closes immediately after save.
      if (widget.target == 'flow') {
        ref
            .read(thoughtsRepositoryProvider)
            .saveThought(content: text, uuid: _capture.id);
      }
      if (widget.target == 'flow') {
        await _capture.discard();
      } else {
        _capture.text = text;
        await _capture.persist();
      }
      if (mounted) Navigator.of(context).pop(text);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not finish. Your transcript is still available for review.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _capture.removeListener(_changed);
    _capture.dispose();
    _review.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _capture.recording;
    final waiting = [
      CapturePhase.connecting,
      CapturePhase.stopping,
      CapturePhase.processing,
    ].contains(_capture.phase);
    final reviewable = !active && !waiting && _capture.text.isNotEmpty;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: !active && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && active) unawaited(_capture.stop());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Discard recording',
              onPressed: _saving
                  ? null
                  : () async {
                      await _capture.discard();
                      if (mounted) _review.clear();
                    },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: VoiceAmbientBackground(
                mode: VoiceSessionMode.transcription,
                phase: active
                    ? VoiceSessionPhase.listening
                    : waiting
                    ? VoiceSessionPhase.thinking
                    : VoiceSessionPhase.paused,
                activity: VoiceAudioActivity(level: _capture.level, pitch: .5),
                reducedMotion: MediaQuery.disableAnimationsOf(context),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          active
                              ? 'Listening on your Android microphone'
                              : waiting
                              ? 'Working on your computer…'
                              : 'Record when you are ready',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _capture.message ?? 'Tap Record when you are ready. Review and correct the transcript before using it.',
                          ),
                        ),
                        if (active)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: LinearProgressIndicator(
                              value: _capture.level,
                              minHeight: 5,
                            ),
                          ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: reviewable
                              ? TextField(
                                  controller: _review,
                                  maxLines: null,
                                  expands: true,
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    labelText: 'Review transcript',
                                    alignLabelWithHint: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    _capture.text = value;
                                    _lastTranscript = value;
                                    unawaited(_capture.persist());
                                  },
                                )
                              : SingleChildScrollView(
                                  child: SelectableText(
                                    _capture.text.isEmpty
                                        ? 'Your words will appear here after short pauses.'
                                        : _capture.text,
                                    style: TextStyle(
                                      fontSize: 21,
                                      height: 1.5,
                                      color: dark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            if (_capture.id == null)
                              FilledButton.icon(
                                onPressed: waiting ? null : _capture.start,
                                icon: const Icon(Icons.mic),
                                label: const Text('Record'),
                              ),
                            if (active)
                              FilledButton.icon(
                                onPressed: _capture.stop,
                                icon: const Icon(Icons.stop),
                                label: const Text('Pause / review'),
                              ),
                            if (_capture.id != null && !active)
                              OutlinedButton(
                                onPressed: waiting ? null : _capture.retry,
                                child: Text(
                                  _capture.accepted
                                      ? 'Retrieve result'
                                      : _capture.bytes > 0
                                      ? 'Retry retained recording'
                                      : 'Try recording again',
                                ),
                              ),
                            if (_capture.canTranscribeAgain && !waiting)
                              OutlinedButton(
                                onPressed: _capture.transcribeAgain,
                                child: const Text('Transcribe original again'),
                              ),
                            if (reviewable)
                              OutlinedButton(
                                onPressed: () =>
                                    _capture.continueRecording(_review.text),
                                child: const Text('Continue recording'),
                              ),
                            if (reviewable)
                              FilledButton(
                                onPressed: _saving ? null : _use,
                                child: Text(
                                  widget.target == 'flow'
                                      ? 'Save thought'
                                      : 'Use transcript',
                                ),
                              ),
                            if (waiting)
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close · keep for recovery'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Audio stays privately on this phone until used or discarded. Expired audio is removed when voice next opens, after 24 hours. Accepted desktop work expires within 24 hours. Audio is not synced; review any misheard words.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
