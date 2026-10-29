import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/local_ai/core/on_device_engine.dart';
import 'package:journal/modules/local_ai/core/operation_runner.dart';

import 'fake_engine.dart';

void main() {
  late FakeOnDeviceEngine engine;
  late OperationRunner runner;
  setUp(() {
    engine = FakeOnDeviceEngine();
    runner = OperationRunner(
      engine,
      Map<String, dynamic>.from(
        jsonDecode(
          File('assets/ai/operations.json').readAsStringSync(),
        )['operations'],
      ),
    );
  });
  test('summary builds desktop messages without sending an operation to the engine', () async {
    await runner
        .complete('summarize-note', 'Untrusted note text.')
        .events
        .drain<void>();
    expect(engine.messages!.first.role, 'system');
    expect(jsonDecode(engine.messages!.last.content), {
      'note': 'Untrusted note text.',
    });
    expect(engine.params, {'temp': 0, 'seed': 42, 'predict': 192});
    expect(engine.responseFormat, isNull);
  });
  test(
    'rewrite preserves the input JSON and reuses the Dart output contract',
    () async {
      final prompt = jsonEncode({'text': 'Original.', 'intent': ''});
      await runner.complete('rewrite-note', prompt).events.drain<void>();
      expect(engine.messages!.last.content, prompt);
      expect(
        () => runner.validate('rewrite-note', '<script>bad</script>'),
        throwsA(isA<EngineFailure>()),
      );
      runner.validate('rewrite-note', 'Clear original text.');
    },
  );
  test('structured operations send the exported response schema', () async {
    await runner
        .complete('suggest-note-template', '{"topic":"Trip"}')
        .events
        .drain<void>();
    expect(engine.responseFormat!['type'], 'json_schema');
    runner.validate(
      'suggest-note-template',
      '{"title":"Trip","body":"## Plans\\n- "}',
    );
    expect(
      () =>
          runner.validate('suggest-note-template', '{"body":"missing title"}'),
      throwsA(isA<EngineFailure>()),
    );
  });
  test('input and output bounds reject without truncation', () {
    expect(
      () => runner.complete('summarize-note', 'a' * 2001),
      throwsA(isA<EngineFailure>()),
    );
    expect(
      () => runner.validate('summarize-note', ''),
      throwsA(isA<EngineFailure>()),
    );
    expect(
      () => runner.validate('summarize-note', 'a' * 2049),
      throwsA(isA<EngineFailure>()),
    );
    expect(
      () => runner.validate('rewrite-note', '\uD800'),
      throwsA(isA<EngineFailure>()),
    );
  });
  test('catalog reasoning bounds reach the primitive without feature code in the engine', () async {
    await runner
        .complete('summarize-note', 'A note.', reasoningBudget: 0)
        .events
        .drain<void>();
    expect(engine.params!['reasoning_budget'], 0);
  });
  test('the caller can cancel the primitive invocation', () async {
    await runner.complete('summarize-note', 'note').cancel();
    expect(engine.cancelled, isTrue);
  });
}
