import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/people/people_models.dart';
import 'package:journal/modules/people/people_pages.dart';
import 'package:journal/modules/people/widgets/burning_paper.dart';

import 'support/people_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader('PeopleTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });
  setUp(
    () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );

  test('reading duration and limits include UTF-8 size', () {
    expect(peopleReadingTime('hi').inSeconds, 20);
    expect(peopleReadingTime('word ' * 100).inSeconds, 50);
    expect(peopleReadingTime('word ' * 500).inSeconds, 210);
    expect(validPeopleNote('word ' * 501), false);
    expect(validPeopleNote('🌿' * 3000), false);
    expect(validPeopleNote('  '), false);
  });
  test(
    'invitations round-trip and reject malformed, expired and oversized input',
    () {
      final invite = FriendInvitation(
        key: peopleBobKey,
        token: peopleSeed,
        name: 'Bob',
        expires: DateTime.now().add(const Duration(minutes: 4)),
      );
      expect(FriendInvitation.parse(invite.encode()).key, peopleBobKey);
      for (final raw in [
        'bad',
        'journal-people:${'x' * 3000}',
        FriendInvitation(
          key: peopleBobKey,
          token: peopleSeed,
          name: 'Bob',
          expires: DateTime.now().subtract(const Duration(seconds: 1)),
        ).encode(),
      ]) {
        expect(
          () => FriendInvitation.parse(raw),
          throwsA(isA<PeopleFailure>()),
        );
      }
    },
  );
  test('friend records validate identity and never contain note fields', () {
    final records = FriendRecords(
      seed: peopleSeed,
      friends: [Person(key: peopleBobKey, name: 'Bob')],
    );
    expect(FriendRecords.fromJson(records.toJson()).friends.single.name, 'Bob');
    expect(
      () => FriendRecords.fromJson({'v': 1, 'seed': 'bad', 'friends': []}),
      throwsFormatException,
    );
    expect(jsonEncode(records.toJson()), isNot(contains('text')));
  });
  test('unknown senders, invalid notes and overflow are discarded; background clears all content', () async {
    final f = PeopleFixture();
    await f.ready();
    f.transport.note('unknown', key: 'd' * 64);
    f.transport.note('word ' * 501);
    expect(f.state.notes, isEmpty);
    for (var i = 0; i < 25; i++) {
      f.transport.note('Private note $i');
    }
    expect(f.state.notes.length, 20);
    final notes = f.state.notes.toList();
    f.controller.openNote(notes.first.id);
    f.controller.foreground(false);
    expect(f.state.notes, isEmpty);
    expect(notes.every((n) => n.text.isEmpty), true);
    f.transport.note('arrived while away');
    expect(f.state.notes, isEmpty);
    expect(f.store.writes, isEmpty);
    f.controller.foreground(true);
    await f.controller.connect();
    expect(f.state.notes, isEmpty);
  });
  test('pairing requires explicit confirmation, consumes invite and persists only identity and friends', () async {
    final f = PeopleFixture(withFriend: false);
    await f.ready();
    await f.controller.createInvite();
    final invitation = f.state.invite!;
    f.controller.foreground(false);
    expect(f.state.invite, same(invitation));
    f.controller.foreground(true);
    await f.controller.connect();
    f.transport.input.add({
      'type': 'candidate',
      'key': peopleBobKey,
      'name': 'Bob',
    });
    expect(f.state.friends, isEmpty);
    expect(f.state.invite, isNull);
    await f.controller.confirm(f.state.candidates.single, true);
    expect(f.state.friends.single.key, peopleBobKey);
    expect(f.transport.confirmations, [true]);
    f.transport.input.add({
      'type': 'candidate',
      'key': 'd' * 64,
      'name': 'Stranger',
    });
    expect(f.state.candidates, isEmpty);
    expect(f.store.records.seed, isNotNull);
    expect(
      f.store.writes.every(
        (w) => w.keys.toSet().difference({'v', 'seed', 'friends'}).isEmpty,
      ),
      true,
    );
  });
  test('rejecting pairing saves no friend and removing a friend drops their notes and trust', () async {
    final f = PeopleFixture();
    await f.ready();
    await f.controller.createInvite();
    f.transport.input.add({
      'type': 'candidate',
      'key': 'd' * 64,
      'name': 'Stranger',
    });
    await f.controller.confirm(f.state.candidates.single, false);
    expect(f.state.friends.length, 1);
    expect(f.transport.confirmations, [false]);
    f.transport.note('Gone on removal');
    final note = f.state.notes.single;
    await f.controller.remove(f.state.friends.single);
    expect(note.text, isEmpty);
    expect(f.state.notes, isEmpty);
    expect(f.transport.trusted, isEmpty);
    f.transport.note('no longer accepted');
    expect(f.state.notes, isEmpty);
  });
  test(
    'failed sends are attempted once and never written to protected storage',
    () async {
      final f = PeopleFixture();
      await f.ready();
      f.transport.failSend = true;
      expect(
        await f.controller.send(peopleBobKey, 'A temporary secret'),
        false,
      );
      expect(f.transport.sends, 1);
      expect(f.store.writes, isEmpty);
      expect(f.state.notes, isEmpty);
      expect(f.transport.stops, greaterThan(0));
    },
  );
  test(
    'reset clears identity, contacts and all live note references',
    () async {
      final f = PeopleFixture();
      await f.ready();
      f.transport.note('Reset me');
      final note = f.state.notes.single;
      await f.controller.clear();
      expect(note.text, isEmpty);
      expect(f.state.notes, isEmpty);
      expect(f.state.friends, isEmpty);
      expect(f.store.records.seed, isNull);
      expect(f.store.clears, 1);
    },
  );
  test('restoration keeps identity and contacts but no prior notes', () async {
    final f = PeopleFixture();
    await f.ready();
    f.transport.note('Do not restore');
    final restored = FriendRecords.fromJson(f.store.records.toJson());
    expect(restored.seed, peopleSeed);
    expect(restored.friends.single.name, 'Bob');
    expect(jsonEncode(restored.toJson()), isNot(contains('Do not restore')));
  });
  test(
    'locked storage fails closed without replacing an existing identity',
    () async {
      final f = PeopleFixture();
      f.store.failLoad = true;
      await f.controller.restore();
      expect(f.transport.starts, 0);
      expect(f.store.writes, isEmpty);
      f.store.failLoad = false;
      await f.controller.restore();
      await f.controller.connect();
      expect(f.store.records.seed, peopleSeed);
    },
  );
  testWidgets('send timeout discards its attempt without an automatic retry', (
    tester,
  ) async {
    final f = PeopleFixture();
    await f.ready();
    f.transport.pendingSend = Completer<void>();
    final sent = f.controller.send(peopleBobKey, 'Timeout secret');
    await tester.pump();
    expect(f.transport.sends, 1);
    await tester.pump(const Duration(seconds: 16));
    expect(await sent, false);
    expect(f.transport.sends, 1);
    expect(f.store.writes, isEmpty);
  });
  testWidgets(
    'invitations expire and incoming alerts open People without previewing text',
    (tester) async {
      final f = PeopleFixture();
      await f.ready();
      await f.controller.createInvite();
      await tester.pump(const Duration(minutes: 5));
      expect(f.state.invite, isNull);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: MaterialApp(
            navigatorKey: key,
            builder: (context, child) =>
                PeopleHost(navigatorKey: key, child: child!),
            home: const Scaffold(body: Text('Diary')),
          ),
        ),
      );
      f.transport.note('Never preview this text');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('A note from Bob'), findsOneWidget);
      expect(find.text('Never preview this text'), findsNothing);
      await tester.tap(find.text('Open People'));
      await tester.pumpAndSettle();
      expect(find.byType(PeoplePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('People supports narrow dark layouts and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = PeopleFixture();
    await f.ready();
    f.transport.note('A private note');
    final capture = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'PeopleTest',
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: RepaintBoundary(key: capture, child: const PeoplePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('PEOPLE_CAPTURES')) {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/private/tmp/journal-people-dark.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('Add friend'));
    await tester.pumpAndSettle();
    await f.controller.createInvite();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.container.dispose();
    await tester.pump();
  });
  testWidgets(
    'timer starts on open, expires monotonically and removes the note text',
    (tester) async {
      final f = PeopleFixture();
      await f.ready();
      f.transport.note('A brief secret');
      final note = f.state.notes.single;
      f.elapsed = const Duration(minutes: 10);
      expect(note.remaining.inSeconds, 20);
      f.controller.openNote(note.id);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: MaterialApp(home: ReadPeopleNotePage(noteId: note.id)),
        ),
      );
      expect(find.text('A brief secret'), findsOneWidget);
      f.elapsed += const Duration(seconds: 21);
      await tester.pump(const Duration(milliseconds: 300));
      expect(note.text, isEmpty);
      expect(find.text('A brief secret'), findsNothing);
      expect(find.text('This note has disappeared.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'People organizes friend, composer and invitation pages with back navigation',
    (tester) async {
      final f = PeopleFixture();
      await f.ready();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: const MaterialApp(home: PeoplePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(find.byType(FriendDetailsPage), findsOneWidget);
      await tester.tap(find.text('Write a note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('people-note-input')),
        'A little secret',
      );
      expect(find.textContaining('20 seconds to read'), findsOneWidget);
      f.controller.foreground(false);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('people-note-input')))
            .controller!
            .text,
        isEmpty,
      );
      f.controller.foreground(true);
      await f.controller.connect();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add friend'));
      await tester.pumpAndSettle();
      expect(find.byType(AddFriendPage), findsOneWidget);
      expect(find.text('Scan invitation'), findsOneWidget);
      expect(find.text('Paste invitation'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'closing reader discards body and unsupported platforms show an explanation',
    (tester) async {
      final f = PeopleFixture();
      await f.ready();
      f.transport.note('Close to discard');
      final note = f.state.notes.single;
      f.controller.openNote(note.id);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: MaterialApp(home: ReadPeopleNotePage(noteId: note.id)),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(note.text, isEmpty);
      final unsupported = PeopleFixture(supported: false);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: unsupported.container,
          child: const MaterialApp(home: PeoplePage()),
        ),
      );
      expect(
        find.text('People is available on Android phones for now.'),
        findsOneWidget,
      );
      expect(unsupported.transport.starts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'envelope opens the note, which burns away over its reading time',
    (tester) async {
      final f = PeopleFixture();
      await f.ready();
      f.transport.note('Words that will burn');
      final note = f.state.notes.single;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: const MaterialApp(home: PeoplePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(note.opened, isFalse);
      await tester.tap(find.text('From Bob'));
      // Seal animation, then the route transition.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(note.opened, isTrue);
      expect(find.byType(BurningPaper), findsOneWidget);
      expect(find.text('Words that will burn'), findsOneWidget);
      f.elapsed += const Duration(seconds: 10);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Words that will burn'), findsOneWidget);
      expect(find.text('10s'), findsOneWidget);
      f.elapsed += const Duration(seconds: 11);
      await tester.pump(const Duration(milliseconds: 300));
      expect(note.text, isEmpty);
      expect(find.byType(BurningPaper), findsNothing);
      expect(find.text('This note has disappeared.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  test('burn front starts off the sheet and ends past it', () {
    const size = Size(360, 600);
    final span = size.height + size.width * .35;
    expect(BurningPaper.front(0, size), lessThan(-150));
    expect(BurningPaper.front(1, size), greaterThan(span + 150));
  });
}
