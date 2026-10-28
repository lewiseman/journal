import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/voice/controllers/diary_conversation.dart';
import 'package:journal/modules/voice/controllers/reply_voice.dart';
import 'package:journal/modules/voice/controllers/talk_session.dart';

import 'diary_conversation_test.dart' show MemoryVoiceStore, computer;

class FakeMic implements TalkMic {
  bool on = false;
  int starts = 0;
  @override
  Future<void> start(void Function(Uint8List pcm) onData) async {
    on = true;
    starts++;
  }

  @override
  Future<void> stop() async => on = false;
}

class FakeVoice extends ReplyVoice {
  final said = <String>[];
  @override
  Future<void> say(String text) async => said.add(text);
  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DiaryConversation conversation;
  late FakeMic mic;
  late FakeVoice voice;
  late TalkSession talk;
  setUp(() {
    conversation = DiaryConversation(
      computer: () => computer,
      dateString: '2026-10-28',
      store: MemoryVoiceStore(),
      autoOpen: false,
    );
    mic = FakeMic();
    voice = FakeVoice();
    talk = TalkSession(conversation: conversation, voice: voice, mic: mic);
  });
  tearDown(() {
    talk.dispose();
    conversation.dispose();
  });

  test('a streamed reply is kept, spoken, then the turn is handed back', () async {
    await talk.handle({'type': 'thinking'});
    await talk.handle({'type': 'token', 'text': 'How was '});
    await talk.handle({'type': 'token', 'text': 'your day?'});
    expect(talk.streaming, 'How was your day?');
    await talk.handle({'type': 'reply', 'text': 'How was your day?'});
    await pumpEventQueue();
    expect(conversation.turns.single, {
      'speaker': 'assistant',
      'text': 'How was your day?',
    });
    expect(voice.said, ['How was your day?']);
    expect(talk.streaming, isEmpty);
    expect(talk.phase, TalkPhase.listening);
  });

  test('the microphone runs only while listening and the transcribed turn is kept', () async {
    await talk.handle({'type': 'listening'});
    expect(mic.on, isTrue);
    await talk.handle({
      'type': 'segment',
      'segment': {'id': 0, 'text': 'I went to the market.'},
    });
    await talk.handle({
      'type': 'segment',
      'segment': {'id': 1, 'text': ' It rained.'},
    });
    expect(talk.heard, 'I went to the market. It rained.');
    await talk.handle({'type': 'endpoint'});
    expect(mic.on, isFalse);
    expect(talk.phase, TalkPhase.transcribing);
    await talk.handle({'type': 'turn', 'text': 'I went to the market. It rained.'});
    expect(conversation.turns.single['speaker'], 'user');
    expect(talk.heard, isEmpty);
  });

  test('errors pause the loop; leaving the foreground keeps replies without speaking them', () async {
    await talk.handle({'type': 'listening'});
    await talk.handle({
      'type': 'error',
      'code': 'BUSY',
      'message': 'The computer is busy.',
    });
    expect(mic.on, isFalse);
    expect(talk.phase, TalkPhase.paused);
    expect(talk.note, 'The computer is busy.');

    await talk.handle({'type': 'listening'});
    await talk.hold();
    expect(mic.on, isFalse);
    await talk.handle({'type': 'reply', 'text': 'What happened next?'});
    expect(conversation.turns.last['text'], 'What happened next?');
    expect(voice.said, isEmpty);
    expect(talk.phase, TalkPhase.paused);
  });
}
