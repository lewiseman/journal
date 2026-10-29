import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/controllers/diary_photo_stories.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/diary/models/diary_photo.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_contract.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_store.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/diary/views/pages/add_diary_photos_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_entry_book.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_contact_sheet.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';
import 'package:journal/modules/diary/views/widgets/diary_reflection_desk.dart';
import 'package:journal/modules/settings/models/local_settings.dart';

import 'support/diary_photo_fixture.dart';

const _captureKey = ValueKey('photo-capture');
final _question = find.byKey(const ValueKey('diary-photo-question'));
final _answer = find.byWidgetPredicate(
  (widget) => widget is TextField && widget.minLines == 3,
);
late Uint8List _photoBytes;
late DiaryFixture _diary;
late MemoryPhotoStore _store;
late MemoryPhotoQuestionStore _questions;
late List<String> _shas;

DiaryPhotoQuestions _generated({bool clear = true}) => DiaryPhotoQuestions(
  observations: 'A market stall stacked with mangoes under a striped awning.',
  clear: clear,
  groups: const [
    ['What brought you to the market that morning?'],
    ['How did the crowd around the stall feel to you?'],
    ['What could you smell near the mangoes?'],
  ],
);

/// Photos the page asked the computer about, in order.
final _asked = <String>[];

/// Whether the fake computer accepts a request and keeps working on it.
var _computerWorking = false;

/// The fake slot, so a test can finish the computer's work.
late _IdleSummary _summary;

/// Shuffle requests the page made: group and questions to avoid.
final _shuffles = <({int group, List<String> avoid})>[];

/// The shared AI task slot with no vision model on the computer: these tests
/// never reach a computer. Controller tests cover real requests.
class _IdleSummary extends NoteSummaryController {
  @override
  NoteSummaryState build() {
    _summary = this;
    return const NoteSummaryState();
  }

  /// Completes the running request with [text], as a computer would.
  void finish(String text) => state = NoteSummaryState(
    phase: 'completed',
    handle: state.handle!.copyWith(phase: 'completed'),
    text: text,
  );

  @override
  Future<void> clear() async => state = const NoteSummaryState();

  @override
  Future<void> startDiaryPhotoQuestions({
    required String date,
    required String photoSha,
    required Uint8List photo,
    String caption = '',
    int group = -1,
    List<String> avoid = const [],
  }) async {
    _asked.add(photoSha);
    if (group >= 0) _shuffles.add((group: group, avoid: avoid));
    if (_computerWorking) {
      state = NoteSummaryState(
        phase: 'running',
        handle: SummaryHandle(
          id: 'photo-task-${_asked.length}',
          noteId: photoSha,
          revision: 'a' * 64,
          computerId: 'desktop',
          created: DateTime.now().millisecondsSinceEpoch,
          operation: diaryPhotoQuestionOperation,
          accepted: true,
          phase: 'running',
          localSource: DiaryPhotoQuestionSource(
            date: date,
            photoSha: photoSha,
            imageSha: 'b' * 64,
            caption: caption,
            group: group,
            avoid: avoid,
          ).encode(),
        ),
      );
      return;
    }
    state = const NoteSummaryState(
      phase: 'error',
      message: 'Download Qwen3-VL and run the image self-test on your computer. The usual questions are still here.',
    );
  }

  @override
  Future<void> cancel() async => state = const NoteSummaryState();
}

// Distinct trailing bytes give each test photo its own identity.
Uint8List _bytes(int index) => Uint8List.fromList([..._photoBytes, index]);

XFile _photo(int index) => XFile.fromData(
  _bytes(index),
  path: '/photo-$index.webp',
  mimeType: 'image/webp',
);

Future<void> _mount(
  WidgetTester tester, {
  Future<List<XFile>> Function()? picker,
  int photos = 2,
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  AppAccent accent = AppAccent.indigo,
  bool reduced = false,
  TextDirection direction = TextDirection.ltr,
  DiaryItem? story,
  bool readOnly = false,
  DateTime? date,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewInsets);
  final themes = AppThemeConfig.themesFor(accent);
  final base = dark ? themes.dark : themes.light;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        diaryPhotoStoriesProvider.overrideWithValue(
          DiaryPhotoStories(_diary.diary, _store),
        ),
        noteSummaryProvider.overrideWith(_IdleSummary.new),
        diaryPhotoQuestionStoreProvider.overrideWithValue(_questions),
      ],
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: 'PhotoTest'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
            ),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => AddDiaryPhotosPage(
                        date: date ?? DateTime(2026, 10, 27),
                        story: story,
                        readOnly: readOnly,
                        imagePicker:
                            picker ?? () async => List.generate(photos, _photo),
                      ),
                    ),
                  ),
                  child: const Text('Open photos'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open photos'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _write(WidgetTester tester, String text) async {
  await tester.ensureVisible(_answer);
  await tester.enterText(_answer, text);
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('DIARY_PHOTO_CAPTURES')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-photos-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() {
    _diary = DiaryFixture.create(DateTime(2026, 10, 27, 12));
    _store = MemoryPhotoStore();
    _questions = MemoryPhotoQuestionStore();
    _asked.clear();
    _shuffles.clear();
    _computerWorking = false;
  });
  tearDown(() => _diary.dispose());

  setUpAll(() async {
    _photoBytes = (await rootBundle.load('assets/images/onboarding/diary.webp'))
        .buffer
        .asUint8List();
    _shas = [
      for (var i = 0; i < 3; i++) await DiaryPhotoStore.digest(_bytes(i)),
    ];
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader('PhotoTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets(
    'cancelled picker can retry and just the photos saves a photo-only story',
    (tester) async {
      var calls = 0;
      await _mount(tester, picker: () async => calls++ == 0 ? [] : [_photo(0)]);
      expect(find.text('Choose photos'), findsOneWidget);
      expect(find.text('Generate questions'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('diary-section-review')));
      expect(find.text('Choose photos'), findsOneWidget);
      expect(find.byType(DiaryPhotoEntryBook), findsNothing);
      await _capture(tester, 'empty');
      await _tap(tester, find.text('Choose photos'));
      expect(find.text('1 of 1 photo'), findsOneWidget);
      await _tap(tester, find.text('Just the photos'));
      expect(find.text('1 photo'), findsOneWidget);
      expect(_answer, findsNothing);
      expect(find.textContaining('Preview only'), findsNothing);
      expect(
        find.text(
          'Photos stay on this device. Sync shares captions and words, not photos.',
        ),
        findsOneWidget,
      );
      expect(_diary.db.diaryBox.count(), 0);
      await _tap(tester, find.text('Save to diary'));
      expect(find.text('Open photos'), findsOneWidget);
      expect(find.byType(AddDiaryPhotosPage), findsNothing);
      final item = _diary.diary.getDay('2026-10-27')!.items.single;
      expect(item.content, isEmpty);
      expect(item.photos.single.path, item.attachmentPaths.single);
      expect(_store.files[item.photos.single.path], _bytes(0));
      expect(_diary.sync.pendingCreations.single.id, item.itemUuid);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('photos swipe, keep their captions, enlarge and can be removed', (
    tester,
  ) async {
    await _mount(tester);
    expect(find.text('Tue, 27 Oct 2026'), findsOneWidget);
    await _capture(tester, 'selection');
    await tester.enterText(find.byType(TextField), 'The slow way home.');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('diary-photo-thumbnail-1')));
    expect(find.text('2 of 2 photos'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.drag(
      find.byKey(const ValueKey('diary-photo-pages')),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('The slow way home.'), findsOneWidget);
    await _tap(tester, find.byType(DiaryPhotoFrame).first);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await _tap(tester, find.byTooltip('Close photo'));
    await tester.tap(find.byTooltip('Remove photo 1'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 photo'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove photo 1'));
    await tester.pumpAndSettle();
    expect(find.text('Choose photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding photos ignores duplicates and keeps existing captions', (
    tester,
  ) async {
    var calls = 0;
    await _mount(
      tester,
      picker: () async => calls++ == 0 ? [_photo(0)] : [_photo(0), _photo(1)],
    );
    await tester.enterText(find.byType(TextField), 'An ordinary lovely thing.');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Add more photos'));
    expect(find.text('1 of 2 photos'), findsOneWidget);
    expect(find.text('An ordinary lovely thing.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each photo and alternate question retain their own answers', (
    tester,
  ) async {
    await _mount(tester);
    await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
    final firstQuestion = tester.widget<Text>(_question).data!;
    await _capture(tester, 'questions');
    await _write(tester, 'We took the long way home.');
    await _tap(
      tester,
      find.byKey(const ValueKey('diary-photo-another-question')),
    );
    expect(tester.widget<Text>(_question).data, isNot(firstQuestion));
    expect(tester.widget<TextField>(_answer).controller!.text, isEmpty);
    await _write(tester, 'The sky was turning pink.');
    await _tap(tester, find.byKey(const ValueKey('diary-photo-thumbnail-1')));
    expect(tester.widget<TextField>(_answer).controller!.text, isEmpty);
    await _write(tester, 'A small celebration with a friend.');
    await _tap(tester, find.byKey(const ValueKey('diary-photo-thumbnail-0')));
    expect(
      tester.widget<TextField>(_answer).controller!.text,
      'The sky was turning pink.',
    );
    await _tap(tester, find.text('The feeling'));
    await _write(tester, 'For a minute, nothing felt rushed.');
    await _tap(tester, find.text('Review'));
    expect(find.text('2 photos · 4 reflections'), findsOneWidget);
    expect(find.text('We took the long way home.'), findsOneWidget);
    expect(find.text('The sky was turning pink.'), findsOneWidget);
    expect(find.text('A small celebration with a friend.'), findsOneWidget);
    expect(find.text('For a minute, nothing felt rushed.'), findsOneWidget);
    await _capture(tester, 'review');
    await _tap(tester, find.text('Revisit this moment').first);
    expect(
      tester.widget<TextField>(_answer).controller!.text,
      'For a minute, nothing felt rushed.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unanswered questions can be advanced through every photo', (
    tester,
  ) async {
    await _mount(tester);
    await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
    await _tap(tester, find.text('Next question'));
    await _tap(tester, find.text('Next question'));
    await _tap(tester, find.text('Next photo'));
    expect(find.text('MOMENT 2 OF 2'), findsOneWidget);
    await _tap(tester, find.text('Next question'));
    await _tap(tester, find.text('Next question'));
    await _tap(tester, find.text('See my entry'));
    expect(find.text('2 photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'header sections keep drafts and Review belongs to the reflection footer',
    (tester) async {
      await _mount(tester, photos: 1);
      final header = find.byType(AppBar);
      for (final label in ['Photos', 'Reflect', 'Entry']) {
        expect(
          find.descendant(of: header, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.text('Photo diary'), findsNothing);
      expect(
        find.descendant(of: header, matching: find.text('Review')),
        findsNothing,
      );
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      await _write(tester, 'A day I want to hold onto.');
      expect(find.text('Skip this question'), findsNothing);
      expect(find.text('Review'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DiaryReflectionControls),
          matching: find.text('Review'),
        ),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const ValueKey('diary-section-photos')));
      expect(find.text('Generate questions'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('diary-section-review')));
      expect(find.text('A day I want to hold onto.'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      expect(
        tester.widget<TextField>(_answer).controller!.text,
        'A day I want to hold onto.',
      );
      await _tap(tester, find.text('Review'));
      expect(find.byType(DiaryPhotoEntryBook), findsOneWidget);
      expect(find.text('A day I want to hold onto.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'swiping the question deck draws alternatives without losing words',
    (tester) async {
      await _mount(tester, photos: 1);
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      final original = tester.widget<Text>(_question).data;
      await _write(
        tester,
        'The way the afternoon light fell across the table.',
      );
      final deck = find.byKey(const ValueKey('diary-reflection-swipe'));
      for (var index = 0; index < 3; index++) {
        await tester.ensureVisible(deck);
        await tester.drag(deck, const Offset(-160, 0));
        await tester.pumpAndSettle();
        if (index == 0) {
          expect(tester.widget<Text>(_question).data, isNot(original));
          expect(tester.widget<TextField>(_answer).controller!.text, isEmpty);
        }
      }
      expect(tester.widget<Text>(_question).data, original);
      expect(
        tester.widget<TextField>(_answer).controller!.text,
        'The way the afternoon light fell across the table.',
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'paper controls work with the keyboard and expose photo enlargement',
    (tester) async {
      await _mount(tester);
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      final feeling = find.byWidgetPredicate(
        (widget) => widget is DiaryInkAction && widget.label == 'The feeling',
      );
      await tester.ensureVisible(feeling);
      final gesture = find.descendant(
        of: feeling,
        matching: find.byType(GestureDetector),
      );
      Focus.of(tester.element(gesture)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DiaryReflectionDesk>(find.byType(DiaryReflectionDesk))
            .selectedGroup,
        1,
      );
      expect(tester.widget<DiaryInkAction>(feeling).selected, isTrue);

      final semantics = tester.ensureSemantics();
      final enlarge = find.bySemanticsLabel('Enlarge photo 1');
      expect(enlarge, findsOneWidget);
      expect(
        tester
            .getSemantics(enlarge)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      semantics.dispose();
      await _tap(tester, find.byTooltip('Enlarge photo 1'));
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await _tap(tester, find.byTooltip('Close photo'));
      expect(find.byType(DiaryReflectionDesk), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system back returns to photos and keeps reflection drafts', (
    tester,
  ) async {
    await _mount(tester, photos: 1);
    await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
    await _write(tester, 'I want to remember the light.');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Generate questions'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
    expect(
      tester.widget<TextField>(_answer).controller!.text,
      'I want to remember the light.',
    );
    await _tap(tester, find.text('Review'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_answer).controller!.text,
      'I want to remember the light.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('prints can be rearranged with their captions and reflections', (
    tester,
  ) async {
    await _mount(tester);
    await tester.enterText(
      find.byType(TextField),
      'The afternoon by the window.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
    await _write(tester, 'I finally had a quiet minute.');
    await _tap(tester, find.text('Review'));
    await _tap(tester, find.text('Edit photos'));
    final first = find.byKey(const ValueKey('diary-photo-thumbnail-0'));
    await tester.ensureVisible(first);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await gesture.moveBy(const Offset(190, 0));
    await tester.pump(const Duration(milliseconds: 450));
    await gesture.moveBy(const Offset(5, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DiaryPhotoContactSheet>(find.byType(DiaryPhotoContactSheet))
          .photos
          .map((photo) => photo.path),
      ['/photo-1.webp', '/photo-0.webp'],
    );
    await _capture(tester, 'reordered');
    expect(find.text('2 of 2 photos'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'The afternoon by the window.',
    );
    await _tap(tester, find.text('Back to entry'));
    final stories = tester
        .widget<DiaryPhotoEntryBook>(find.byType(DiaryPhotoEntryBook))
        .stories;
    expect(stories.first.caption, isEmpty);
    expect(stories.last.caption, 'The afternoon by the window.');
    expect(
      stories.last.reflections.single.answer,
      'I finally had a quiet minute.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'entry annotations toggle and editing photos keeps the written story',
    (tester) async {
      await _mount(tester, photos: 1);
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      final question = tester.widget<Text>(_question).data!;
      await _write(tester, 'The whole street smelled like rain.');
      await _tap(tester, find.text('Review'));
      expect(find.text(question), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('diary-entry-prompts-0')));
      expect(find.text(question), findsOneWidget);
      expect(find.text('The whole street smelled like rain.'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('diary-entry-prompts-0')));
      expect(find.text(question), findsNothing);
      await _tap(tester, find.text('Edit photos'));
      await tester.enterText(find.byType(TextField), 'After the rain.');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('1 photo · 1 reflection'), findsOneWidget);
      expect(find.text('After the rain.'), findsOneWidget);
      expect(find.text('The whole street smelled like rain.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picker errors are recoverable and do not lose chosen photos', (
    tester,
  ) async {
    var calls = 0;
    await _mount(
      tester,
      picker: () async {
        calls++;
        if (calls == 1) throw PlatformException(code: 'photo_access_denied');
        if (calls == 3) throw StateError('picker unavailable');
        return [_photo(0)];
      },
    );
    expect(find.textContaining('Photo access is off.'), findsOneWidget);
    await _tap(tester, find.text('Choose photos'));
    await _tap(tester, find.byTooltip('Add more photos'));
    expect(find.text('1 of 1 photo'), findsOneWidget);
    expect(
      find.text('Your photos couldn’t be opened. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving while picker is open safely ignores its late result', (
    tester,
  ) async {
    final pending = Completer<List<XFile>>();
    await _mount(tester, picker: () => pending.future);
    await _tap(tester, find.byTooltip('Close without saving'));
    pending.complete([_photo(0)]);
    await tester.pumpAndSettle();
    expect(find.text('Open photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  DiaryItem savedStory() => _diary.diary.getDay('2026-10-27')!.items.single;

  testWidgets(
    'a reflected story saves order, captions and reviewed words, then reopens',
    (tester) async {
      await _mount(tester);
      await tester.enterText(find.byType(TextField), 'Leaving the market.');
      FocusManager.instance.primaryFocus?.unfocus();
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      final question = tester.widget<Text>(_question).data!;
      await _write(tester, 'Mangoes everywhere.');
      await _tap(tester, find.text('Review'));
      await _tap(tester, find.text('Save to diary'));
      final item = savedStory();
      expect(item.photos.map((photo) => photo.caption), [
        'Leaving the market.',
        '',
      ]);
      expect(item.photos.first.reflections.single.question, question);
      expect(
        item.photos.first.reflections.single.answer,
        'Mangoes everywhere.',
      );
      expect(item.photos.first.sha256, hasLength(64));
      expect(item.content, 'Leaving the market.\n\nMangoes everywhere.');
      expect(_diary.diary.getDay('2026-10-27')!.visibleItems, hasLength(1));

      // Reopen after a restart: the record and private copies come back.
      _diary.restart();
      final reopened = savedStory();
      await tester.pumpWidget(const SizedBox());
      await _mount(tester, story: reopened);
      expect(find.byType(DiaryPhotoEntryBook), findsOneWidget);
      expect(find.text('Leaving the market.'), findsOneWidget);
      expect(find.text('Mangoes everywhere.'), findsOneWidget);
      expect(find.text('2 photos · 1 reflection'), findsOneWidget);
      expect(
        tester
            .widget<DiaryPhotoEntryBook>(find.byType(DiaryPhotoEntryBook))
            .stories
            .map((story) => story.bytes),
        [_bytes(0), _bytes(1)],
      );
      expect(find.text('Save changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing reorders, removes a photo and releases only its private copy',
    (tester) async {
      await _mount(tester, photos: 3);
      await _tap(tester, find.text('Just the photos'));
      await _tap(tester, find.text('Save to diary'));
      final before = savedStory();
      expect(_store.files, hasLength(3));
      await tester.pumpWidget(const SizedBox());
      await _mount(tester, story: before);
      await _tap(tester, find.text('Edit photos'));
      expect(find.text('Back to entry'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove photo 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Now first.');
      FocusManager.instance.primaryFocus?.unfocus();
      await _tap(tester, find.text('Back to entry'));
      await _tap(tester, find.text('Save changes'));
      final after = savedStory();
      expect(after.itemUuid, before.itemUuid);
      expect(after.photos.map((photo) => photo.id), [
        before.photos[1].id,
        before.photos[2].id,
      ]);
      expect(after.photos.first.caption, 'Now first.');
      expect(_store.files.keys, after.attachmentPaths);
      expect(_diary.sync.pendingCreations, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing or going back never saves, new or reopened', (
    tester,
  ) async {
    await _mount(tester);
    await _tap(tester, find.text('Just the photos'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Close without saving'));
    expect(find.byType(AddDiaryPhotosPage), findsNothing);
    expect(_diary.db.diaryBox.count(), 0);
    expect(_store.files, isEmpty);

    _diary.diary.addTimelineItem(
      dateString: '2026-10-27',
      content: '',
      photos: [
        for (final i in [0, 1])
          DiaryPhoto(id: 'p$i', path: 'diary_photos/p$i.jpg', caption: 'c$i'),
      ],
    );
    _store.files['diary_photos/p0.jpg'] = _bytes(0);
    _store.files['diary_photos/p1.jpg'] = _bytes(1);
    final saved = savedStory();
    await tester.pumpWidget(const SizedBox());
    await _mount(tester, story: saved);
    await _tap(tester, find.text('Edit photos'));
    await tester.tap(find.byTooltip('Remove photo 1'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 photo'), findsOneWidget);
    await _tap(tester, find.byTooltip('Close without saving'));
    expect(find.byType(AddDiaryPhotosPage), findsNothing);
    expect(savedStory().toJson(), saved.toJson());
    expect(_store.files, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a photo from another device shows as missing and survives an edit',
    (tester) async {
      _diary.diary.addTimelineItem(
        dateString: '2026-10-27',
        content: 'From the tablet.',
        photos: const [
          DiaryPhoto(
            id: 'remote',
            path: 'diary_photos/remote.jpg',
            caption: 'From the tablet.',
          ),
        ],
      );
      await _mount(tester, story: savedStory());
      expect(find.text('Not on this device'), findsWidgets);
      expect(
        find.textContaining('kept only on the device that added them'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Edit photos'));
      await tester.enterText(find.byType(TextField), 'Still from the tablet.');
      FocusManager.instance.primaryFocus?.unfocus();
      await _tap(tester, find.text('Back to entry'));
      await _tap(tester, find.text('Save changes'));
      final item = savedStory();
      expect(item.photos.single.path, 'diary_photos/remote.jpg');
      expect(item.photos.single.caption, 'Still from the tablet.');
      expect(_store.files, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read-only devices can open a saved story but not change it', (
    tester,
  ) async {
    _diary.diary.addTimelineItem(
      dateString: '2026-10-27',
      content: '',
      photos: const [DiaryPhoto(id: 'p', path: 'diary_photos/p.jpg')],
    );
    _store.files['diary_photos/p.jpg'] = _bytes(0);
    await _mount(tester, story: savedStory(), readOnly: true);
    expect(find.byType(DiaryPhotoEntryBook), findsOneWidget);
    expect(find.text('Edit photos'), findsNothing);
    expect(find.text('Find a few words'), findsNothing);
    expect(find.text('Save changes'), findsNothing);
    expect(
      find.text('Saved stories can be changed on your primary device.'),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const ValueKey('diary-section-photos')));
    expect(find.byType(DiaryPhotoEntryBook), findsOneWidget);
    await _tap(tester, find.text('Done'));
    expect(find.byType(AddDiaryPhotosPage), findsNothing);
  });

  testWidgets(
    'a secondary device saves today and keeps a past-day draft on refusal',
    (tester) async {
      _diary.makeSecondary();
      await _mount(tester, photos: 1);
      await _tap(tester, find.text('Just the photos'));
      await _tap(tester, find.text('Save to diary'));
      expect(savedStory().photos, hasLength(1));
      expect(_diary.sync.pendingCreations, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      await _mount(tester, photos: 1, date: DateTime(2026, 10, 26));
      await _tap(tester, find.text('Just the photos'));
      await _tap(tester, find.text('Save to diary'));
      expect(
        find.text('This device can only add diary items for today.'),
        findsOneWidget,
      );
      expect(find.byType(DiaryPhotoEntryBook), findsOneWidget);
      expect(_diary.diary.getDay('2026-10-26'), isNull);
      expect(_store.files, hasLength(1));
    },
  );

  testWidgets('a failed copy saves nothing and keeps the story open', (
    tester,
  ) async {
    _store.failWrites = true;
    await _mount(tester);
    await _tap(tester, find.text('Just the photos'));
    await _tap(tester, find.text('Save to diary'));
    expect(
      find.text('Your photo story couldn’t be saved. It’s still here.'),
      findsOneWidget,
    );
    expect(find.text('2 photos'), findsOneWidget);
    expect(_diary.db.diaryBox.count(), 0);
    _store.failWrites = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Save to diary'));
    expect(savedStory().photos, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final config in [
    (
      size: Size(320, 700),
      scale: 1.8,
      dark: false,
      accent: AppAccent.teal,
      direction: TextDirection.ltr,
    ),
    (
      size: Size(390, 844),
      scale: 1.0,
      dark: true,
      accent: AppAccent.plum,
      direction: TextDirection.rtl,
    ),
    (
      size: Size(844, 390),
      scale: 1.0,
      dark: false,
      accent: AppAccent.walnut,
      direction: TextDirection.ltr,
    ),
  ]) {
    testWidgets(
      'photo flow fits with large type, dark mode and keyboard: $config',
      (tester) async {
        await _mount(
          tester,
          size: config.size,
          scale: config.scale,
          dark: config.dark,
          accent: config.accent,
          direction: config.direction,
          reduced: true,
        );
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          config.dark
              ? 'selection-dark'
              : 'selection-${config.size.width.toInt()}',
        );
        await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          config.dark ? 'dark' : 'compact-${config.size.width.toInt()}',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        await _write(tester, 'A small thing, remembered.');
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Review'));
        expect(find.text('A small thing, remembered.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          config.dark ? 'entry-dark' : 'entry-${config.size.width.toInt()}',
        );
      },
    );
  }

  testWidgets(
    'I02: generated questions replace the usual ones, with no info panel, and save their group and origin',
    (tester) async {
      _questions.results[_shas[0]] = _generated(clear: false);
      await _mount(tester);
      await _tap(tester, find.text('Generate questions'));
      expect(_asked, [_shas[1]], reason: 'photo 1 already has questions');
      expect(
        find.byKey(const ValueKey('diary-photo-generating')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('diary-photo-status')), findsNothing);
      expect(find.textContaining('A market stall stacked'), findsNothing);
      expect(
        tester.widget<Text>(_question).data,
        'What brought you to the market that morning?',
      );
      await _write(tester, 'Sunday shopping with Ama.');
      ScaffoldMessenger.of(tester.element(_question)).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Review'));
      await _tap(tester, find.text('Save to diary'));
      final first = savedStory().photos.first;
      expect(first.seen, '');
      expect(first.reflections.single.group, 'moment');
      expect(first.reflections.single.fromPhoto, true);
      expect(savedStory().content, 'Sunday shopping with Ama.');
    },
  );

  testWidgets(
    'I02: answers written to the usual questions survive when photo questions arrive',
    (tester) async {
      await _mount(tester);
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      final usual = tester.widget<Text>(_question).data!;
      await _write(tester, 'It was loud and bright.');
      // A result arrives (here: cached) while the person is elsewhere.
      _questions.results[_shas[0]] = _generated();
      await _tap(tester, find.byKey(const ValueKey('diary-section-photos')));
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      expect(
        tester.widget<Text>(_question).data,
        'What brought you to the market that morning?',
      );
      // The earlier answer is still reachable in its group.
      await _tap(
        tester,
        find.byKey(const ValueKey('diary-photo-another-question')),
      );
      expect(tester.widget<Text>(_question).data, usual);
      expect(
        tester.widget<TextField>(_answer).controller!.text,
        'It was loud and bright.',
      );
      await _tap(tester, find.text('Review'));
      await _tap(tester, find.text('Save to diary'));
      final reflection = savedStory().photos.first.reflections.single;
      expect(reflection.question, usual);
      expect(reflection.group, 'moment');
      expect(reflection.fromPhoto, false);
    },
  );

  testWidgets(
    'I02: Reflect shows loading until the computer finishes, and Stop returns to the usual questions',
    (tester) async {
      _computerWorking = true;
      await _mount(tester);
      // The spinner never settles: pump frames instead of settling.
      await tester.ensureVisible(find.text('Generate questions'));
      await tester.tap(find.text('Generate questions'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_asked, [_shas[0]], reason: 'one photo at a time');
      expect(
        find.byKey(const ValueKey('diary-photo-generating')),
        findsOneWidget,
      );
      expect(find.text('Writing questions for your photos…'), findsOneWidget);
      expect(_question, findsNothing);
      expect(find.text('Next question'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('diary-photo-stop')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('diary-photo-generating')),
        findsNothing,
      );
      expect(
        tester.widget<Text>(_question).data,
        'What made you want to capture this moment?',
      );
      expect(_asked, [_shas[0]], reason: 'the waiting photo was never sent');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'I02: without a vision model, Generate questions keeps the usual questions and says why once',
    (tester) async {
      await _mount(tester, photos: 3);
      await _tap(tester, find.text('Generate questions'));
      expect(_asked, [_shas[0]], reason: 'the refusal is not repeated');
      expect(
        find.byKey(const ValueKey('diary-photo-generating')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('diary-photo-message')), findsOneWidget);
      expect(find.textContaining('Download Qwen3-VL'), findsOneWidget);
      expect(
        tester.widget<Text>(_question).data,
        'What made you want to capture this moment?',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'I02: the question card has no label or counter, and shuffle asks the computer for a new question in that section',
    (tester) async {
      _computerWorking = true;
      await _mount(tester);
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      expect(find.text('SAMPLE QUESTION'), findsNothing);
      expect(find.text('1 / 3'), findsNothing);
      final first = tester.widget<Text>(_question).data!;
      await tester.tap(
        find.byKey(const ValueKey('diary-photo-another-question')),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_asked, [_shas[0]]);
      expect(_shuffles.single.group, 0);
      expect(_shuffles.single.avoid, contains(first));
      expect(
        find.byKey(const ValueKey('diary-photo-question-loading')),
        findsOneWidget,
      );
      _summary.finish(
        jsonEncode({
          'observations': 'A market.',
          'clear': true,
          'moment': [first, 'Who were you hoping to bump into at the market?'],
          'feeling': ['How did the noise feel?'],
          'little': ['What could you smell?'],
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('diary-photo-question-loading')),
        findsNothing,
      );
      expect(
        tester.widget<Text>(_question).data,
        'Who were you hoping to bump into at the market?',
        reason: 'the first new question, skipping one already shown',
      );
      await _write(tester, 'Nobody, I wanted quiet.');
      await _tap(tester, find.text('Review'));
      await _tap(tester, find.text('Save to diary'));
      final saved = savedStory().photos.first.reflections.single;
      expect(saved.question, 'Who were you hoping to bump into at the market?');
      expect(saved.group, 'moment');
      expect(saved.fromPhoto, true);
      expect(_questions.results, isEmpty, reason: 'one question, not a set');
    },
  );

  testWidgets(
    'I02: without the computer, shuffle moves to the next question it already has',
    (tester) async {
      await _mount(tester);
      await _tap(tester, find.byKey(const ValueKey('diary-section-reflect')));
      await _tap(
        tester,
        find.byKey(const ValueKey('diary-photo-another-question')),
      );
      expect(
        tester.widget<Text>(_question).data,
        'What was happening just before you took this photo?',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
