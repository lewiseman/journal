import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/common.dart' hide DiaryDayEntity;
import 'package:journal/config/diary_typography.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/models/diary_ai_conversation.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_photo.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_curl.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';

final _date = DateTime(2026, 10, 26);
final _capture = GlobalKey();

DiaryItem _item(
  String id,
  String text, {
  int photos = 0,
  bool conversation = false,
}) => DiaryItem(
  itemUuid: id,
  createdAt: _date,
  updatedAt: _date,
  content: text,
  photos: [
    for (var i = 0; i < photos; i++)
      DiaryPhoto(
        id: '$id-$i',
        path: 'diary_photos/${i % 2}.webp',
        caption: 'Already in the prose.',
      ),
  ],
  aiConversation: conversation
      ? DiaryAiConversation(
          createdAt: _date,
          turns: const [
            {'speaker': 'assistant', 'text': 'What stayed with you?'},
            {'speaker': 'user', 'text': '  '},
            {
              'speaker': 'user',
              'text': 'The quiet on the way home. There was still a little light between the trees.',
            },
          ],
        )
      : null,
);

DiaryDayEntity _day() =>
    DiaryDayEntity(
        dateString: '2026-10-26',
        dayTitle: 'Ordinary, in a good way.',
        dayMood: '{"emoji":"😌","name":"Calm","category":"calm"}',
      )
      ..items = [
        _item(
          'morning',
          'The house was quiet when I opened the curtains. Coffee, a little sun, and nowhere to rush.\n\nI want to keep a little room for mornings like this.',
          photos: 1,
        ),
        _item(
          'walk',
          'We took the long way home. The small things stayed with me.',
          photos: 4,
          conversation: true,
        ),
        _item('talk', '', conversation: true),
      ];

Future<void> _mount(
  WidgetTester tester,
  DiaryDayEntity day, {
  double width = 390,
  double scale = 1,
  bool dark = false,
  TextDirection direction = TextDirection.ltr,
}) async {
  final themes = AppThemeConfig.themesFor(AppAccent.walnut);
  await tester.pumpWidget(
    MaterialApp(
      theme: (dark ? themes.dark : themes.light).copyWith(
        textTheme: (dark ? themes.dark : themes.light).textTheme.apply(
          fontFamily: 'Roboto',
          fontFamilyFallback: ['Apple Color Emoji'],
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: width,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: direction,
                  child: RepaintBoundary(
                    key: _capture,
                    child: CustomPaint(
                      painter: DiaryPaperPainter(
                        shape: DiaryPaperShape.forDate(_date),
                        paper: (dark ? themes.dark : themes.light)
                            .colorScheme
                            .surface,
                        ink: (dark ? themes.dark : themes.light)
                            .colorScheme
                            .onSurface,
                      ),
                      child: DiaryAccess(
                        canEdit: true,
                        today: _date,
                        child: DiaryDayContent(day: day),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Let real file IO and the test clock both progress while decoding fixtures.
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
    if (tester
        .renderObjectList<RenderImage>(find.byType(RawImage))
        .every((image) => image.image != null)) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory root;
  late DiaryPhotoStore previous;
  setUpAll(() async {
    await (FontLoader(
      'Caveat',
    )..addFont(rootBundle.load('assets/fonts/Caveat-Medium.ttf'))).load();
    await (FontLoader(
      'Lora',
    )..addFont(rootBundle.load('assets/fonts/Lora-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final roboto = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (roboto.existsSync()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(await roboto.readAsBytes())),
          ))
          .load();
    }
    final emoji = File('/System/Library/Fonts/Apple Color Emoji.ttc');
    if (emoji.existsSync()) {
      await (FontLoader('Apple Color Emoji')..addFont(
            Future.value(ByteData.sublistView(await emoji.readAsBytes())),
          ))
          .load();
    }
    root = await Directory.systemTemp.createTemp('diary-notebook-test-');
    for (final (i, name) in ['diary', 'cover'].indexed) {
      final data = await rootBundle.load('assets/images/onboarding/$name.webp');
      final file = File('${root.path}/diary_photos/$i.webp');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    previous = DiaryPhotoStore.instance;
  });
  setUp(() {
    DiaryPhotoStore.instance = DiaryPhotoStore(
      supportDirectory: () async => root,
    );
  });
  tearDownAll(() async {
    DiaryPhotoStore.instance = previous;
    await root.delete(recursive: true);
  });

  for (final config in [
    (
      name: 'light',
      width: 390.0,
      scale: 1.0,
      dark: false,
      direction: TextDirection.ltr,
    ),
    (
      name: 'dark',
      width: 390.0,
      scale: 1.0,
      dark: true,
      direction: TextDirection.ltr,
    ),
    (
      name: 'large-rtl',
      width: 240.0,
      scale: 2.0,
      dark: true,
      direction: TextDirection.rtl,
    ),
    (
      name: 'tablet',
      width: 700.0,
      scale: 1.0,
      dark: false,
      direction: TextDirection.ltr,
    ),
  ]) {
    testWidgets('notebook renders mixed entries: ${config.name}', (
      tester,
    ) async {
      await _mount(
        tester,
        _day(),
        width: config.width,
        scale: config.scale,
        dark: config.dark,
        direction: config.direction,
      );
      expect(find.text('5 images'), findsNothing);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('diary-add-images')))
            .getSemanticsData()
            .value,
        '5 photos',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('diary-image-count')))
            .data,
        '5',
      );
      expect(find.text('Mon, 26 Oct 2026'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
      final pile = find.byKey(const ValueKey('diary-photo-stack-walk'));
      expect(pile, findsOneWidget);
      final pileImages = find.descendant(
        of: pile,
        matching: find.byType(Image),
      );
      final pileRects = pileImages
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      expect(pileRects, hasLength(2));
      expect(pileRects[0].overlaps(pileRects[1]), isTrue);
      expect(
        pileRects[0].intersect(pileRects[1]).width,
        greaterThan(pileRects[0].width * .65),
      );
      expect(find.text('Already in the prose.'), findsNothing);
      expect(find.text('From a conversation'), findsOneWidget);
      expect(find.text('Open conversation'), findsOneWidget);
      final excerpt = tester.widget<Text>(
        find.byKey(const ValueKey('diary-conversation-excerpt-talk')),
      );
      expect(excerpt.data, startsWith('The quiet on the way home.'));
      expect(excerpt.maxLines, 2);
      expect(
        tester
            .widget<Text>(find.text('Ordinary, in a good way.'))
            .style!
            .fontFamily,
        'Caveat',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('morning')))
            .style!
            .fontFamily,
        'Lora',
      );
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(
        images,
        hasLength(3),
      ); // One single print, then two decoded prints in a stack.
      for (final image in images) {
        final provider = image.image as ResizeImage;
        expect(provider.width, lessThanOrEqualTo(640));
        expect(provider.height, provider.width);
        expect(provider.policy, ResizeImagePolicy.fit);
      }
      expect(
        tester.renderObject(find.byType(DiaryDayContent)).needsCompositing,
        isFalse,
      );
      if (const bool.fromEnvironment('NOTEBOOK_CAPTURES')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/journal-notebook-${config.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'missing photos and conversations without user words remain visible',
    (tester) async {
      final day = DiaryDayEntity(dateString: '2026-10-26')
        ..items = [
          _item('missing', '', photos: 1).copyWith(
            photos: const [
              DiaryPhoto(id: 'missing', path: 'diary_photos/missing.webp'),
            ],
          ),
          _item('no-user', '', conversation: true).copyWith(
            aiConversation: DiaryAiConversation(
              createdAt: _date,
              turns: const [
                {'speaker': 'assistant', 'text': 'How was your day?'},
              ],
            ),
          ),
        ];
      await _mount(tester, day);
      expect(find.text('1 image'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('diary-image-count')))
            .data,
        '1',
      );
      expect(find.text('Not on this device'), findsOneWidget);
      expect(find.text('Conversation saved.'), findsOneWidget);
      expect(find.text('Open conversation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'typography is held across a partial turn and updated after cancellation',
    (tester) async {
      final fonts = ValueNotifier(const DiaryTypography());
      addTearDown(fonts.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<DiaryTypography>(
          valueListenable: fonts,
          builder: (context, value, _) => MaterialApp(
            theme: AppThemeConfig.lightTheme.copyWith(extensions: [value]),
            home: Scaffold(
              body: DiaryAccess(
                canEdit: true,
                today: _date,
                child: DiaryPage(clock: () => _date, diaries: [_day()]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final center = tester.getCenter(
        find.byKey(const ValueKey('diary-active-paper')),
      );
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(25, 0));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w is DiaryPaperCurl && !w.flat),
        findsOneWidget,
      );
      fonts.value = DiaryTypography(
        title: const DiaryTypography().title.copyWith(fontFamily: 'Lora'),
      );
      await tester.pump(const Duration(milliseconds: 400));
      for (final title in tester.widgetList<Text>(
        find.text('Ordinary, in a good way.'),
      )) {
        expect(title.style!.fontFamily, 'Caveat');
      }
      await gesture.cancel();
      await tester.pumpAndSettle();
      for (final title in tester.widgetList<Text>(
        find.text('Ordinary, in a good way.'),
      )) {
        expect(title.style!.fontFamily, 'Lora');
      }
      expect(tester.takeException(), isNull);
    },
  );
}
