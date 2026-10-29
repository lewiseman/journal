import 'dart:typed_data';

enum AiTask { writing, image, transcription }

enum EnginePhase { stopped, starting, ready, working, interrupted, failed }

class EngineState {
  const EngineState(this.phase, [this.message]);
  final EnginePhase phase;
  final String? message;
}

class ModelFile {
  const ModelFile({required this.id, required this.path, required this.format});
  final String id, path, format;
}

class AiMessage {
  const AiMessage(this.role, this.content);
  final String role, content;
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

sealed class CompletionEvent {
  const CompletionEvent();
}

class CompletionToken extends CompletionEvent {
  const CompletionToken(this.text);
  final String text;
}

class CompletionDone extends CompletionEvent {
  const CompletionDone({this.outputLimit = false});
  final bool outputLimit;
}

sealed class ImageEvent {
  const ImageEvent();
}

class ImageProgress extends ImageEvent {
  const ImageProgress(this.step, this.total);
  final int step, total;
}

class ImageDone extends ImageEvent {
  const ImageDone(this.bytes, {this.seed = 0});
  final Uint8List bytes;
  final int seed;
}

/// A unique, cancellable invocation. Cancelling must also stop native work.
class EngineRun<T> {
  const EngineRun(this.events, this.cancel);
  final Stream<T> events;
  final Future<void> Function() cancel;
}

class EngineFailure implements Exception {
  const EngineFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => '$code: $message';
}

/// Only inference primitives cross this seam. Engines never receive operations,
/// notes, prompts owned by the app, download credentials or feature contracts.
abstract interface class OnDeviceEngine {
  String get id;
  String get displayName;
  Set<AiTask> get supportedTasks;
  Set<String> get supportedModelFormats;
  Stream<EngineState> get state;
  Future<void> start();
  Future<void> stop();
  Future<void> load(ModelFile file, AiTask task);
  Future<void> unload(AiTask task);
  EngineRun<CompletionEvent> complete(
    List<AiMessage> messages, {
    required Map<String, dynamic> params,
    Map<String, dynamic>? responseFormat,
  });
  EngineRun<ImageEvent> generateImage(
    String prompt, {
    required int width,
    required int height,
    required int steps,
    required int seed,
    String negativePrompt = '',
  });
}
