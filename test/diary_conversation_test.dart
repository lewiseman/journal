import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/voice/controllers/diary_conversation.dart';
import 'package:journal/modules/voice/controllers/voice_store.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

class MemoryVoiceStore extends VoiceStore {
  Map<String, dynamic>? data;
  @override
  Future<Map<String, dynamic>?> load(String target) async => data == null
      ? null
      : jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  @override
  Future<void> save(String target, Map<String, dynamic> value) async {
    data = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }

  @override
  Future<void> clear(String target) async {
    data = null;
  }
}

class ConversationTransport implements CompanionTransport {
  ConversationTransport(this.store);
  final MemoryVoiceStore store;
  Map<String, dynamic>? job, input;
  int submissions = 0;
  bool loseAcceptance = true, complete = false;
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    if (route == '/v1/challenge') return {'nonce': 'A' * 43};
    if (method == 'POST' && route == '/v1/jobs') {
      expect(store.data?['pending']?['id'], body!['id']);
      submissions++;
      input = body;
      job = {
        'id': body['id'],
        'device': 'phone-device',
        'operation': 'diary.conversation',
        'state': 'queued',
      };
      if (loseAcceptance) {
        loseAcceptance = false;
        throw const CompanionFailure('UNAVAILABLE', 'Lost acceptance reply');
      }
      return job!;
    }
    if (method == 'GET') {
      if (job == null)
        throw const CompanionFailure('NOT_FOUND', 'No accepted task');
      return {
        ...job!,
        if (complete) ...{
          'state': 'completed',
          'text': 'I walked home. I was happy.',
        },
      };
    }
    return {'ok': true};
  }

  @override
  void close() {}
}

final computer = TrustedComputer(
  id: 'desktop',
  name: 'Synthetic desktop',
  pin: 'a' * 64,
  endpoint: Uri.parse('https://127.0.0.1:47921'),
  seed: base64Encode(List.filled(32, 7)),
  publicKey: base64Encode(List.filled(32, 8)),
  deviceId: 'phone-device',
);
void main() {
  test('lost acceptance recovers one request; original turns and draft survive restart', () async {
    final store = MemoryVoiceStore();
    final peer = ConversationTransport(store);
    final session = DiaryConversation(
      computer: () => computer,
      dateString: '2026-10-28',
      store: store,
      transportFactory: () => peer,
    );
    await session.add('I walked home. I was happy.');
    await session.request('draft');
    expect(peer.submissions, 1);
    expect(session.pending, isNotNull);
    final prompt = jsonDecode(peer.input!['prompt'] as String) as Map;
    expect(prompt.containsKey('diary'), isFalse);
    expect(prompt.containsKey('translateToEnglish'), isFalse);
    expect(prompt['turns'], hasLength(1));
    session.dispose();
    peer.complete = true;
    final recovered = DiaryConversation(
      computer: () => computer,
      dateString: '2026-10-28',
      store: store,
      transportFactory: () => peer,
    );
    addTearDown(recovered.dispose);
    await recovered.restore();
    expect(peer.submissions, 1);
    expect(recovered.pending, isNull);
    expect(recovered.turns.single['text'], 'I walked home. I was happy.');
    expect(recovered.draft, 'I walked home. I was happy.');
    expect(store.data?['draft'], recovered.draft);
  });
  test('correcting a user turn invalidates the draft; saved sessions cannot mutate or silently regenerate', () async {
    final session = DiaryConversation(
      computer: () => computer,
      dateString: '2026-10-28',
      store: MemoryVoiceStore(),
    );
    addTearDown(session.dispose);
    await session.add('We met on Friday.');
    session.draft = 'We met on Friday.';
    await session.correct(0, 'We met on Saturday.');
    expect(session.draft, isEmpty);
    expect(session.turns.single['text'], 'We met on Saturday.');
    session.saved = true;
    await session.add('A delayed extra turn');
    await session.request('draft');
    expect(session.turns, hasLength(1));
    expect(session.pending, isNull);
  });
  test('a fresh conversation is opened by the companion and its question is handed to speech', () async {
    final store = MemoryVoiceStore();
    final peer = ConversationTransport(store)
      ..loseAcceptance = false
      ..complete = true;
    final spoken = <String>[];
    final session = DiaryConversation(
      computer: () => computer,
      dateString: '2026-10-28',
      store: store,
      transportFactory: () => peer,
      onReply: spoken.add,
      diary: () => [
        {'daysAgo': 1, 'text': 'Interview at the bank tomorrow.'},
      ],
    );
    addTearDown(session.dispose);
    await session.restore();
    final prompt = jsonDecode(peer.input!['prompt'] as String) as Map;
    expect(prompt['action'], 'open');
    expect(prompt['turns'], isEmpty);
    expect((prompt['diary'] as List).single['text'], contains('Interview'));
    // The fake accepts as queued; retrieve as the poll would.
    await session.retrieve();
    expect(session.pending, isNull);
    expect(session.turns.single['speaker'], 'assistant');
    expect(spoken, [session.turns.single['text']]);
    await session.open();
    expect(peer.submissions, 1);
  });
}
