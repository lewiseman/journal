import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';
import 'package:journal/modules/voice/controllers/diary_conversation.dart';
import 'package:journal/modules/voice/controllers/mic_permission.dart';
import 'package:journal/modules/voice/controllers/talk_session.dart';
import 'package:journal/modules/voice/views/pages/diary_talk_page.dart';
import 'package:journal/modules/voice/models/voice_session.dart';
import 'package:journal/modules/voice/views/widgets/voice_ambient_background.dart';

import 'diary_conversation_test.dart' show MemoryVoiceStore, computer;
import 'support/sync_fixture.dart' show TestDevice;
import 'talk_session_test.dart' show FakeMic, FakeVoice;

/// Writes a fixed draft instead of asking the computer.
class DraftingConversation extends DiaryConversation {
  DraftingConversation()
    : super(
        computer: () => computer,
        dateString: '2026-10-28',
        store: MemoryVoiceStore(),
        autoOpen: false,
        keep: false,
      );
  String result = 'A calm day.';
  @override
  Future<void> request(String action) async {
    if (action == 'draft') {
      draft = result;
      message = 'The computer is not reachable.';
      update();
    }
  }
}

class FakePermission extends MicPermission {
  FakePermission(this.initial) : super(supported: true);
  MicStatus initial;
  MicStatus? onRequest;
  int requests = 0, settings = 0;

  @override
  Future<MicStatus> check() async {
    status = initial;
    notifyListeners();
    return status;
  }

  @override
  Future<MicStatus> request() async {
    requests++;
    if (status == MicStatus.blocked) {
      await openSettings();
      return status;
    }
    status = initial = onRequest ?? status;
    notifyListeners();
    return status;
  }

  @override
  Future<void> openSettings() async => settings++;
}

class CountingTalk extends TalkSession {
  CountingTalk({required super.conversation, required super.voice})
    : super(mic: FakeMic());
  int starts = 0;
  @override
  Future<void> start() async => starts++;
}

typedef DiaryItemLike = (String, int);

/// The ambient background never settles, so pump through route transitions.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final today = DateTime(2026, 10, 28, 12);
  late DraftingConversation conversation;
  late CountingTalk talk;
  late Directory directory;
  late ObjectBox db;
  late DiaryRepository diary;
  setUp(() {
    conversation = DraftingConversation();
    talk = CountingTalk(conversation: conversation, voice: FakeVoice());
    directory = Directory.systemTemp.createTempSync('diary-talk-');
    db = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: directory.path),
    );
    diary = DiaryRepository(
      db: db,
      device: TestDevice('phone'),
      sync: SyncStateStore(
        storage: JournalSyncKeyValueStore(db.store),
        deviceId: 'phone',
        now: () => today,
      ),
    );
  });
  tearDown(() {
    talk.dispose();
    conversation.dispose();
    db.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> mount(WidgetTester tester, FakePermission permission) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diaryRepositoryProvider.overrideWithValue(diary)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DiaryTalkPage(
                    date: today,
                    conversation: conversation,
                    voice: talk.voice,
                    talk: talk,
                    permission: permission,
                  ),
                ),
              ),
              child: const Text('Open talk'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open talk'));
    await settle(tester);
  }

  List<DiaryItemLike> saved() => [
    for (final item in diary.getDay('2026-10-28')?.items ?? const [])
      (item.content, item.aiConversation?.turns.length ?? 0),
  ];

  testWidgets('a granted microphone starts the session straight away', (
    tester,
  ) async {
    await mount(tester, FakePermission(MicStatus.granted));
    expect(talk.starts, 1);
    expect(find.byKey(const ValueKey('voice-mic-card')), findsNothing);
  });

  testWidgets('a denied microphone waits, and allowing it starts the session', (
    tester,
  ) async {
    final permission = FakePermission(MicStatus.denied)
      ..onRequest = MicStatus.granted;
    await mount(tester, permission);
    expect(talk.starts, 0);
    expect(find.text('Microphone is off'), findsOneWidget);
    expect(find.text('Waiting for your microphone'), findsOneWidget);
    expect(
      tester
          .widget<VoiceAmbientBackground>(find.byType(VoiceAmbientBackground))
          .phase,
      VoiceSessionPhase.paused,
    );

    await tester.tap(find.text('Allow microphone'));
    await tester.pump();
    await tester.pump();
    expect(permission.requests, 1);
    expect(talk.starts, 1);
    expect(find.byKey(const ValueKey('voice-mic-card')), findsNothing);
  });

  testWidgets('a blocked microphone opens settings and starts on return', (
    tester,
  ) async {
    final permission = FakePermission(MicStatus.blocked);
    await mount(tester, permission);
    expect(find.text('Microphone is blocked'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(permission.settings, 1);
    expect(talk.starts, 0);

    permission.initial = MicStatus.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(talk.starts, 1);
  });

  testWidgets('loading and speaking share colours but not motion', (
    tester,
  ) async {
    await mount(tester, FakePermission(MicStatus.granted));
    VoiceSessionPhase phase() => tester
        .widget<VoiceAmbientBackground>(find.byType(VoiceAmbientBackground))
        .phase;
    expect(phase(), VoiceSessionPhase.thinking);
    talk
      ..phase = TalkPhase.speaking
      ..streaming = 'How was your day?'
      ..notifyListeners();
    await tester.pump();
    expect(phase(), VoiceSessionPhase.speaking);
    expect(find.text('How was your day?'), findsOneWidget);
    expect(find.byTooltip('Answer now'), findsOneWidget);
  });

  testWidgets('each turn is kept on a new diary item as it happens', (
    tester,
  ) async {
    await mount(tester, FakePermission(MicStatus.granted));
    expect(conversation.turns, isEmpty);
    await conversation.append('assistant', 'How was your day?');
    expect(saved(), isEmpty, reason: 'no words from you yet');
    await conversation.append('user', 'Calm.');
    expect(saved(), [('', 2)]);
    await conversation.append('assistant', 'What made it calm?');
    expect(saved(), [('', 3)]);
  });

  testWidgets('Finish writes the draft into the entry and closes', (
    tester,
  ) async {
    await mount(tester, FakePermission(MicStatus.granted));
    await conversation.append('assistant', 'How was your day?');
    await conversation.append('user', 'Calm.');
    await tester.tap(find.text('Finish'));
    await settle(tester);
    expect(saved(), [('A calm day.', 2)]);
    expect(
      diary.getDay('2026-10-28')!.items.single.aiConversation!.draftedAt,
      isNotNull,
    );
    expect(find.byType(DiaryTalkPage), findsNothing);
  });

  testWidgets('a failed draft keeps the conversation and says so', (
    tester,
  ) async {
    conversation.result = '';
    await mount(tester, FakePermission(MicStatus.granted));
    await conversation.append('assistant', 'How was your day?');
    await conversation.append('user', 'Calm.');
    await tester.tap(find.text('Finish'));
    await settle(tester);
    expect(find.text("Couldn't write your entry"), findsOneWidget);
    expect(saved(), [('', 2)]);
    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.byType(DiaryTalkPage), findsNothing);
  });
}
