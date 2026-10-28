import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/models/diary_ai_conversation.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import 'diary_conversation.dart';
import 'voice_store.dart';

/// A diary conversation backed by the paired computer and recent entries.
/// The diary item holds the turns, so nothing is kept in the local store.
DiaryConversation diaryConversation(
  WidgetRef ref, {
  required String dateString,
  VoiceStore? store,
}) => DiaryConversation(
  dateString: dateString,
  store: store,
  keep: false,
  // The live talk session asks the first question itself.
  autoOpen: false,
  computer: () {
    if (ref.read(accountResetProvider).blocksDataAccess) {
      throw const CompanionFailure('RESET', 'Account reset is in progress.');
    }
    final c = ref.read(companionControllerProvider).selected;
    if (c == null) {
      throw const CompanionFailure(
        'UNAVAILABLE',
        'Pair your computer in More → Local QVAC.',
      );
    }
    return c;
  },
  // The same selection the daily question uses: today's latest entries,
  // then recent days, within a small budget.
  diary: () {
    final source = DailyQuestionSource.select(
      today: dateString,
      day: ref.read(diaryRepositoryProvider).getDay,
    );
    return [
      for (final e in [...source.today, ...source.prior])
        {'daysAgo': source.ago(e), 'text': e.text},
    ];
  },
);

/// Moves a conversation left in the old 24-hour local store into its diary
/// day, so it is never offered again as the start of a new talk.
Future<void> adoptLeftoverDiaryTalk(
  DiaryRepository diary, {
  VoiceStore? store,
}) async {
  final local = store ?? VoiceStore();
  try {
    final v = await local.load('diary');
    if (v == null) return;
    final turns = [
      for (final t in v['turns'] as List) Map<String, String>.from(t as Map),
    ];
    final conversation = DiaryAiConversation(
      turns: turns,
      createdAt: DateTime.fromMillisecondsSinceEpoch(v['created'] as int),
    );
    if (v['saved'] != true && conversation.hasUserTurn) {
      final draft = (v['draft'] as String? ?? '').trim();
      diary.saveAiConversation(
        dateString: v['date'] as String,
        itemUuid: v['id'] as String,
        conversation: conversation,
        content: draft.isEmpty ? null : draft,
      );
    }
    await local.clear('diary');
  } catch (_) {
    // Locked storage or a read-only device: leave it for the next open.
  }
}
