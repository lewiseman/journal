import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

void _record(DiaryPaperStamp stamp, Size size) {
  final recorder = ui.PictureRecorder();
  stamp.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

void main() {
  testWidgets('paper stamps reuse textures across sizes, dates and opacity', (
    tester,
  ) async {
    final before = DiaryPaperStamp.debugTextureBuilds;
    for (var day = 1; day <= 90; day++) {
      _record(
        DiaryPaperStamp(
          paper: const Color(0xfff8f0e7),
          ink: const Color(0xff382c23),
          variant: DateTime(2026, 1, day).weekday,
          edgeScale: .25 + day % 3 * .05,
          opacity: .5 + day % 4 * .1,
        ),
        Size(44.0 + day % 20, 50.0 + day % 30),
      );
    }
    expect(DiaryPaperStamp.debugTextureBuilds - before, 3);
    for (var theme = 0; theme < 20; theme++) {
      _record(
        DiaryPaperStamp(
          paper: Color(0xfffafafa - theme * 0x010101),
          ink: const Color(0xff222222),
        ),
        const Size(60, 80),
      );
      expect(DiaryPaperStamp.debugCachedTextures, lessThanOrEqualTo(12));
    }
  });

  for (final paper in [const Color(0xfffaf8fc), const Color(0xff17151d)]) {
    testWidgets('paper stamp stays opaque and flattens to surface: $paper', (
      tester,
    ) async {
      const size = Size(120, 160);
      for (final flatten in [0.0, 1.0]) {
        final recorder = ui.PictureRecorder();
        DiaryPaperStamp(
          paper: paper,
          ink: const Color(0xff888888),
          shadow: false,
          flatten: flatten,
        ).paint(Canvas(recorder), size);
        final picture = recorder.endRecording();
        final data = (await tester.runAsync(() async {
          final image = await picture.toImage(120, 160);
          final result = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return result;
        }))!;
        picture.dispose();
        final color = paper.toARGB32();
        for (var y = 0; y < 160; y++) {
          for (var x = 0; x < 120; x++) {
            if (flatten == 0 && (x < 24 || x >= 96 || y < 24 || y >= 136)) {
              continue;
            }
            final offset = (y * 120 + x) * 4;
            expect(data.getUint8(offset), (color >> 16) & 255);
            expect(data.getUint8(offset + 1), (color >> 8) & 255);
            expect(data.getUint8(offset + 2), color & 255);
            expect(data.getUint8(offset + 3), 255);
          }
        }
        if (flatten == 0) expect(data.getUint8(3), 0);
      }
    });
  }

  if (const bool.fromEnvironment('DIARY_BENCHMARK')) {
    testWidgets('paper control recording benchmark', (tester) async {
      const stamp = DiaryPaperStamp(
        paper: Color(0xfffaf8fc),
        ink: Color(0xff22212a),
        edgeScale: .35,
      );
      const full = DiaryPaperPainter(
        shape: DiaryPaperShape(seed: 42),
        paper: Color(0xfffaf8fc),
        ink: Color(0xff22212a),
        shadow: true,
      );
      void recordFull(int i) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(.35);
        full.paint(canvas, Size((44.0 + i % 20) / .35, (50.0 + i % 30) / .35));
        recorder.endRecording().dispose();
      }

      for (var i = 0; i < 30; i++) {
        recordFull(i);
        _record(stamp, Size(44.0 + i % 20, 50.0 + i % 30));
      }
      const iterations = 300;
      final fullTime = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        recordFull(i);
      }
      fullTime.stop();
      final stampTime = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        _record(stamp, Size(44.0 + i % 20, 50.0 + i % 30));
      }
      stampTime.stop();
      // This measures CPU display-list recording, not device frame rate.
      debugPrint(
        'PAPER_RECORDING: full=${fullTime.elapsedMicroseconds ~/ iterations}us '
        'stamp=${stampTime.elapsedMicroseconds ~/ iterations}us per control',
      );
    });
  }
}
