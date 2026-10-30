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
import 'package:journal/modules/people/widgets/friend_avatar.dart';
import 'package:journal/modules/people/people_pages.dart';
import 'package:journal/modules/people/widgets/burning_paper.dart';
import 'package:journal/modules/people/widgets/note_arrival_banner.dart';

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
      await tester.tap(find.text('Open Friends'));
      await tester.pumpAndSettle();
      expect(find.byType(PeoplePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'arrival notices replace older senders and clear when backgrounded',
    (tester) async {
      final f = PeopleFixture();
      final mayaKey = 'd' * 64;
      f.store.records = FriendRecords(
        seed: peopleSeed,
        friends: [
          Person(key: peopleBobKey, name: 'Bob'),
          Person(key: mayaKey, name: 'Maya'),
        ],
      );
      await f.ready();
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
      f.transport.note('First private note');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      f.transport.note('Second private note', key: mayaKey);
      await tester.pumpAndSettle();
      expect(find.text('A note from Bob'), findsNothing);
      expect(find.text('A note from Maya'), findsOneWidget);
      expect(find.text('Second private note'), findsNothing);
      expect(f.state.notes.every((n) => !n.opened), isTrue);
      await tester.tap(find.byTooltip('Dismiss note alert'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteArrivalBanner), findsNothing);
      expect(f.state.notes, hasLength(2));
      f.transport.note('Third private note');
      await tester.pump();
      f.transport.note('Fourth private note', key: mayaKey);
      f.controller.foreground(false);
      await tester.pumpAndSettle();
      f.controller.foreground(true);
      await f.controller.connect();
      await tester.pumpAndSettle();
      expect(find.byType(NoteArrivalBanner), findsNothing);
      expect(f.state.notes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.container.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'arrival notices fit large text, respect reduced motion and expire without opening notes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = PeopleFixture();
      await f.ready();
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: MaterialApp(
            navigatorKey: key,
            theme: ThemeData.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.8),
                disableAnimations: true,
              ),
              child: PeopleHost(navigatorKey: key, child: child!),
            ),
            home: const Scaffold(body: Text('Diary')),
          ),
        ),
      );
      f.transport.note('Still sealed');
      await tester.pump();
      await tester.pump();
      expect(find.byType(NoteArrivalBanner), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(
        find.byKey(const ValueKey('people-arrival-open')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Dismiss note alert').hitTestable(),
        findsOneWidget,
      );
      expect(f.state.notes.single.opened, isFalse);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.byType(NoteArrivalBanner), findsNothing);
      expect(f.state.notes.single.text, 'Still sealed');
      expect(f.state.notes.single.opened, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.container.dispose();
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
    await tester.tap(find.byKey(const ValueKey('people-add-friend')));
    await tester.pumpAndSettle();
    await f.controller.createInvite();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.container.dispose();
    await tester.pump();
  });
  testWidgets(
    'friend list and inbox coordinate scrolling and inherit the app theme',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = PeopleFixture();
      f.store.records = FriendRecords(
        seed: peopleSeed,
        friends: [
          Person(key: peopleBobKey, name: 'Bob'),
          for (var i = 0; i < 40; i++)
            Person(
              key: i.toRadixString(16).padLeft(64, '0'),
              name: 'Friend $i',
            ),
        ],
      );
      await f.ready();
      f.transport.note('Only visible after opening');
      const background = Color(0xfff4f5ff);
      final theme = ThemeData(
        scaffoldBackgroundColor: background,
        fontFamily: 'PeopleTest',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: MaterialApp(theme: theme, home: const PeoplePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        background,
      );
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      final avatar = find.byType(FriendAvatar).first;
      final bob = find.text('Bob');
      expect(tester.getRect(avatar).right, lessThan(tester.getRect(bob).left));
      expect(tester.widget<Text>(bob).style?.fontFamily, 'PeopleTest');
      expect(find.text('Only visible after opening'), findsNothing);
      expect(find.textContaining('Keep both apps open'), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('people-friends-view')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsNothing);
      final firstVisibleTile = find.byType(ListTile).hitTestable().first;
      final visibleName =
          (tester.widget<ListTile>(firstVisibleTile).title! as Text).data!;
      final visibleFriend = find.text(visibleName);
      final position = tester.getTopLeft(visibleFriend);
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(find.text('From Bob'), findsOneWidget);
      expect(find.text('Only visible after opening'), findsNothing);
      await tester.tap(find.text('Friends'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(visibleFriend), position);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.container.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'empty states explain invitations and notes without a permanent footer',
    (tester) async {
      final f = PeopleFixture(withFriend: false);
      await f.ready();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: const MaterialApp(home: PeoplePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your people, right here'), findsOneWidget);
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(find.text('No notes waiting'), findsOneWidget);
      expect(find.textContaining('Keep both apps open'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('people-add-friend')));
      await tester.pumpAndSettle();
      expect(find.text('Make a new connection'), findsOneWidget);
      await tester.tap(find.text('Create invitation'));
      await tester.pump();
      expect(
        find.bySemanticsLabel('Private friend invitation QR code'),
        findsOneWidget,
      );
      expect(find.text('Make a new connection'), findsNothing);
      expect(find.textContaining('Expires in'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text('Scan invitation'), findsOneWidget);
      expect(find.text('Paste invitation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.container.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'pasted invitations still require confirmation and return to friends',
    (tester) async {
      final f = PeopleFixture(withFriend: false);
      await f.ready();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: const MaterialApp(home: PeoplePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('people-add-friend')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      final invitation = FriendInvitation(
        key: peopleBobKey,
        token: peopleSeed,
        name: 'Bob',
        expires: DateTime.now().add(const Duration(minutes: 4)),
      );
      await tester.enterText(find.byType(TextField), invitation.encode());
      await tester.tap(find.text('Accept pasted invitation'));
      await tester.pumpAndSettle();
      expect(find.text('Add Bob?'), findsOneWidget);
      expect(f.state.friends, isEmpty);
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();
      expect(find.byType(AddFriendPage), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      expect(f.state.friends.single.key, peopleBobKey);
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Friend options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove friend'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Bob?'), findsOneWidget);
      expect(f.state.friends, hasLength(1));
      await tester.tap(find.text('Keep friend'));
      await tester.pumpAndSettle();
      expect(f.state.friends, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.container.dispose();
      await tester.pump();
    },
  );

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
    'short notes have a minimum sheet size, centered text and reachable controls',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final layout in [
        (size: const Size(390, 844), scale: 1.0),
        (size: const Size(320, 568), scale: 1.8),
        (size: const Size(844, 390), scale: 1.0),
      ]) {
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        final f = PeopleFixture();
        await f.ready();
        f.transport.note('See you soon.');
        final note = f.state.notes.single;
        f.controller.openNote(note.id);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'PeopleTest'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(layout.scale)),
                child: child!,
              ),
              home: ReadPeopleNotePage(noteId: note.id),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final paper = tester.getRect(
          find.byKey(const ValueKey('people-reading-paper')),
        );
        final text = tester.getRect(
          find.byKey(const ValueKey('people-reading-text')),
        );
        final countdown = tester.getRect(
          find.byKey(const ValueKey('people-reading-countdown')),
        );
        expect(paper.height, greaterThanOrEqualTo(280));
        expect(text.center.dx, closeTo(paper.center.dx, .1));
        expect(text.center.dy, closeTo(paper.center.dy, .1));
        if (layout.size.width > layout.size.height * 1.3) {
          expect(countdown.left, greaterThanOrEqualTo(paper.right));
        } else {
          expect(countdown.bottom, lessThanOrEqualTo(paper.top));
        }
        expect(
          find.byKey(const ValueKey('people-reading-text')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('people-close-note')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.container.dispose();
        await tester.pump();
      }
    },
  );

  testWidgets('long notes scroll while the timer and Close stay visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = PeopleFixture();
    await f.ready();
    f.transport.note(
      'A quiet afternoon, warm coffee, and plenty of stories. ' * 45,
    );
    final note = f.state.notes.single;
    f.controller.openNote(note.id);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: MaterialApp(home: ReadPeopleNotePage(noteId: note.id)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final close = find.byKey(const ValueKey('people-close-note'));
    final countdown = find.byKey(const ValueKey('people-reading-countdown'));
    final buttonRect = tester.getRect(close);
    final timerRect = tester.getRect(countdown);
    final scroll = find.byKey(const ValueKey('people-reading-scroll'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('people-reading-text')))
          .textAlign,
      TextAlign.start,
    );
    await tester.drag(scroll, const Offset(0, -700));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.getRect(close), buttonRect);
    expect(tester.getRect(countdown), timerRect);
    expect(close.hitTestable(), findsOneWidget);
    f.elapsed = note.duration + const Duration(seconds: 1);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('This note has disappeared.'), findsOneWidget);
    expect(find.byType(BurningPaper), findsNothing);
    expect(close.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.container.dispose();
    await tester.pump();
  });

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
      await tester.tap(find.byKey(const ValueKey('people-add-friend')));
      await tester.pumpAndSettle();
      expect(find.byType(AddFriendPage), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
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
        find.text('Friends works on Android phones for now.'),
        findsOneWidget,
      );
      expect(unsupported.transport.starts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('inbox opens the note, which burns away over its reading time', (
    tester,
  ) async {
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
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From Bob'));
    // Finish the route transition.
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
  });
  test('burn front starts off the sheet and ends past it', () {
    const size = Size(360, 600);
    final span = size.height + size.width * .35;
    expect(BurningPaper.front(0, size), lessThan(-150));
    expect(BurningPaper.front(1, size), greaterThan(span + 150));
  });
}
