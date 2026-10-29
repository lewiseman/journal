import 'dart:async';

import 'package:journal/modules/local_ai/core/on_device_engine.dart';

class FakeOnDeviceEngine implements OnDeviceEngine {
  List<AiMessage>? messages;
  Map<String, dynamic>? params, responseFormat;
  List<CompletionEvent> output = const [
    CompletionToken('A short factual summary.'),
    CompletionDone(),
  ];
  bool cancelled = false, started = false;
  int loads = 0;
  Stream<CompletionEvent>? completionStream;
  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake engine';
  @override
  Set<AiTask> get supportedTasks => {AiTask.writing, AiTask.image};
  @override
  Set<String> get supportedModelFormats => {'gguf'};
  @override
  Stream<EngineState> get state => const Stream.empty();
  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  Future<void> load(ModelFile file, AiTask task) async {
    loads++;
  }

  @override
  Future<void> unload(AiTask task) async {}
  @override
  EngineRun<CompletionEvent> complete(
    List<AiMessage> messages, {
    required Map<String, dynamic> params,
    Map<String, dynamic>? responseFormat,
  }) {
    this.messages = messages;
    this.params = params;
    this.responseFormat = responseFormat;
    return EngineRun(completionStream ?? Stream.fromIterable(output), () async {
      cancelled = true;
    });
  }

  @override
  EngineRun<ImageEvent> generateImage(
    String prompt, {
    required int width,
    required int height,
    required int steps,
    required int seed,
    String negativePrompt = '',
  }) => EngineRun(const Stream.empty(), () async {
    cancelled = true;
  });
}
