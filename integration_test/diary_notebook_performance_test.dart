// Synthetic diary only: no account, journal database, or saved photos are opened.
// Run before/after on the same phone with --profile and --no-uninstall.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/models/diary_ai_conversation.dart';
import 'package:journal/modules/diary/models/diary_photo.dart';
import 'package:journal/modules/diary/views/pages/diary_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/sample_diaries.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('warmed diary swipes and long-page scrolling', (tester) async {
    final parent = await Directory(
      '${(await getTemporaryDirectory()).path}/notebook-profile',
    ).create(recursive: true);
    final root = await parent.createTemp();
    final previousStore = DiaryPhotoStore.instance;
    DiaryPhotoStore.instance = DiaryPhotoStore(
      supportDirectory: () async => root,
    );
    final photos = <DiaryPhoto>[];
    for (final (index, name) in ['diary', 'cover', 'birthdays'].indexed) {
      final data = await rootBundle.load('assets/images/onboarding/$name.webp');
      final file = File('${root.path}/diary_photos/$index.webp');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
      photos.add(DiaryPhoto(id: '$index', path: 'diary_photos/$index.webp'));
    }
    final today = DateTime(2026, 10, 25);
    final days = buildSampleDiaries(today);
    for (final day in days.take(5)) {
      day.items = [
        for (final (index, item) in day.items.indexed)
          item.copyWith(
            photos: index == 0 ? photos : [],
            aiConversation: index == 1
                ? DiaryAiConversation(
                    createdAt: item.createdAt,
                    turns: const [
                      {'speaker': 'user', 'text': 'A quiet morning outside.'},
                      {'speaker': 'assistant', 'text': 'What stayed with you?'},
                    ],
                  )
                : null,
          ),
      ];
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeConfig.lightTheme,
        home: Scaffold(
          body: DiaryAccess(
            canEdit: true,
            today: today,
            child: DiaryPage(clock: () => today, diaries: days),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paper = find.byKey(const ValueKey('diary-active-paper'));
    Future<void> swipe(double dx) async {
      await tester.timedDragFrom(
        tester.getCenter(paper),
        Offset(dx, 0),
        const Duration(milliseconds: 320),
      );
      await tester.pumpAndSettle();
    }

    for (var i = 0; i < 3; i++) {
      await swipe(220);
      await swipe(-220);
    }
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(collect);
    for (var i = 0; i < 12; i++) {
      await swipe(220);
      await swipe(-220);
    }
    await swipe(220);
    for (var i = 0; i < 6; i++) {
      await tester.timedDragFrom(
        tester.getCenter(paper),
        const Offset(0, -450),
        const Duration(milliseconds: 420),
      );
      await tester.pumpAndSettle();
      await tester.timedDragFrom(
        tester.getCenter(paper),
        const Offset(0, 650),
        const Duration(milliseconds: 420),
      );
      await tester.pumpAndSettle();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    SchedulerBinding.instance.removeTimingsCallback(collect);
    double percentile(Iterable<Duration> values) {
      final sorted = values.map((v) => v.inMicroseconds / 1000).toList()
        ..sort();
      return sorted[((sorted.length - 1) * .95).round()];
    }

    expect(timings, isNotEmpty);
    final report = {
      'phase': const String.fromEnvironment('NOTEBOOK_PHASE'),
      'frames': timings.length,
      'build_p95_ms': percentile(timings.map((t) => t.buildDuration)),
      'raster_p95_ms': percentile(timings.map((t) => t.rasterDuration)),
      'platform': Platform.operatingSystemVersion,
    };
    binding.reportData = report;
    debugPrint('NOTEBOOK_PROFILE ${jsonEncode(report)}');
    await tester.pumpWidget(const SizedBox.shrink());
    DiaryPhotoStore.instance = previousStore;
    await root.delete(recursive: true);
  });
}
