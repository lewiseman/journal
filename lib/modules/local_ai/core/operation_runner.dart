import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../notes/transform/transform_contract.dart';
import '../../notes/metadata/note_help_contract.dart';
import '../../notes/images/note_background_gen.dart';
import '../../flow/reflection/thought_reflection_contract.dart';
import '../../diary/suggestions/diary_suggestion_contract.dart';
import '../../diary/questions/daily_question_contract.dart';
import '../../diary/history/diary_history_contract.dart';
import '../../recall/recall_question_contract.dart';
import 'on_device_engine.dart';

/// Prompts and generation bounds are exported from desktop, never duplicated in
/// the engine. Context used for validation stays in Dart.
class OperationRunner {
  OperationRunner(this.engine, this.operations);
  final OnDeviceEngine engine;
  final Map<String, dynamic> operations;
  static Future<Map<String, dynamic>> loadOperations() async =>
      Map<String, dynamic>.from(
        (jsonDecode(await rootBundle.loadString('assets/ai/operations.json'))
            as Map)['operations'],
      );
  bool supports(String operation) => operations.containsKey(operation);
  Map<String, dynamic> spec(String operation) {
    final value = operations[operation];
    if (value is! Map) {
      throw const EngineFailure(
        'NOT_READY',
        'This operation needs the companion.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  EngineRun<CompletionEvent> complete(
    String operation,
    String prompt, {
    int? reasoningBudget,
  }) {
    final s = spec(operation), limits = s['limits'] as Map;
    if (!_bounded(prompt, limits['inputBytes'] as int)) {
      throw const EngineFailure(
        'INVALID_INPUT',
        'The request exceeds this operation’s input limit. Nothing was truncated.',
      );
    }
    final user = switch (s['userEncoding']) {
      'note' => jsonEncode({'note': prompt}),
      'thought' => jsonEncode({'thought': prompt}),
      _ => prompt,
    };
    final params = Map<String, dynamic>.from(s['params'] as Map);
    if (params['seed'] == 'random') {
      params['seed'] = Random.secure().nextInt(0x7fffffff);
    }
    params['predict'] = limits['outputTokens'];
    if (reasoningBudget != null) params['reasoning_budget'] = reasoningBudget;
    return engine.complete(
      [AiMessage('system', s['system'] as String), AiMessage('user', user)],
      params: params,
      responseFormat: s['responseFormat'] == null
          ? null
          : Map<String, dynamic>.from(s['responseFormat']),
    );
  }

  void validate(String operation, String text, {String? source}) {
    final limit = (spec(operation)['limits'] as Map)['outputBytes'] as int;
    if (!_bounded(text, limit)) {
      throw const EngineFailure(
        'INVALID_OUTPUT',
        'The model returned an empty or invalid result.',
      );
    }
    try {
      if (transformOperations.containsKey(operation)) {
        if (!validTransformOutput(text)) {
          throw const FormatException('Invalid transformation');
        }
      } else {
        switch (operation) {
          case thoughtReflectionOperation:
            if (!validThoughtReflectionLine(text)) {
              throw const FormatException('Invalid reflection');
            }
          case noteTemplateOperation:
            NoteTemplate.parse(text);
          case noteIdeasOperation:
            parseNoteIdeas(text);
          case noteMetadataOperation:
            NoteMetadataSuggestions.parse(
              text,
              NoteMetadataSource.decode(source!),
            );
          case diarySuggestionOperation:
            DiarySuggestions.parse(text, DiarySuggestionSource.decode(source!));
          case dailyQuestionOperation:
            try {
              DailyQuestion.parse(text, DailyQuestionSource.decode(source!));
            } on DailyQuestionRejected {
              /* Valid envelope, declined by the feature. */
            }
          case historyOperation:
            try {
              DiaryHistoryAnswer.parse(
                text,
                DiaryHistorySelection.decode(source!),
              );
            } on DiaryAnswerRejected {
              /* Feature explains the content rejection. */
            }
          case noteQuestionOperation || thoughtQuestionOperation:
            try {
              RecallQuestionAnswer.parse(
                text,
                RecallQuestionSelection.decode(source!),
              );
            } on RecallAnswerRejected {
              /* Feature explains the content rejection. */
            }
          case noteBackgroundOperation:
            NoteBackgroundResult.parse(text);
          case 'summarize-note':
            break;
          default:
            throw const FormatException('Unsupported output contract');
        }
      }
    } catch (_) {
      throw const EngineFailure(
        'INVALID_OUTPUT',
        'The result did not pass this operation’s output contract.',
      );
    }
  }

  EngineRun<ImageEvent> image(String operation, String prompt) {
    final s = spec(operation), j = jsonDecode(prompt) as Map;
    final request = NoteBackgroundRequest(
      noteId: '',
      prompt: j['prompt'],
      tone: j['tone'],
      background: const {},
    );
    request.request(); // Reuse the feature’s bounded input contract.
    final template = (s['prompts'] as Map)[request.tone] as String;
    return engine.generateImage(
      template.replaceAll('{prompt}', request.prompt.trim()),
      width: s['width'],
      height: s['height'],
      steps: s['limits']['steps'],
      seed: Random.secure().nextInt(0x7fffffff),
      negativePrompt: s['negativePrompt'],
    );
  }
}

bool _bounded(String text, int limit) =>
    text.trim().isNotEmpty &&
    utf8.encode(text).length <= limit &&
    !RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(text) &&
    !text.runes.any((u) => u >= 0xd800 && u <= 0xdfff);
