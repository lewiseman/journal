import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';

const _size = Size(300, 420);

Future<ByteData> _paint(
  WidgetTester tester, {
  required DiaryPaperShape shape,
  required Color paper,
  required Color ink,
  bool reverse = false,
}) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  const capture = ValueKey('paper-material');
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: capture,
        child: CustomPaint(
          painter: DiaryPaperPainter(
            shape: shape,
            paper: paper,
            ink: ink,
            reverse: reverse,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(capture),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data;
  }))!;
}

int _offset(int x, int y) => (y * _size.width.toInt() + x) * 4;

double _rimWear(ByteData data, Color paper) {
  final base = paper.toARGB32();
  final channels = [(base >> 16) & 255, (base >> 8) & 255, base & 255];
  double difference = 0;
  int count = 0;
  for (var y = 30; y < 390; y++) {
    for (var x = 6; x < 17; x++) {
      final offset = _offset(x, y);
      if (data.getUint8(offset + 3) != 255) continue;
      for (var channel = 0; channel < 3; channel++) {
        difference += (data.getUint8(offset + channel) - channels[channel])
            .abs();
        count++;
      }
    }
  }
  return difference / count;
}

void main() {
  test(
    'date-seeded outlines are stable, bounded and soften into a rectangle',
    () {
      final shape = DiaryPaperShape.forDate(DateTime(2026, 10, 25));
      final same = DiaryPaperShape.forDate(DateTime(2026, 10, 25, 23));
      final different = DiaryPaperShape.forDate(DateTime(2026, 10, 24));
      expect(shape, same);
      expect(shape.outline(_size), orderedEquals(same.outline(_size)));
      expect(
        shape.outline(_size),
        isNot(orderedEquals(different.outline(_size))),
      );
      expect(
        (Offset.zero & _size).contains(shape.path(_size).getBounds().topLeft),
        isTrue,
      );
      expect(
        shape.path(_size).getBounds().right,
        lessThanOrEqualTo(_size.width),
      );
      expect(
        shape.path(_size).getBounds().bottom,
        lessThanOrEqualTo(_size.height),
      );
      final expanded = DiaryPaperShape.forDate(
        DateTime(2026, 10, 25),
        expansion: 1,
      );
      expect(expanded.path(_size).getBounds(), Offset.zero & _size);
      expect(expanded.path(_size).contains(const Offset(.1, .1)), isTrue);
      expect(expanded.path(_size).contains(const Offset(299.9, 419.9)), isTrue);
    },
  );

  for (final config in [
    (
      name: 'light',
      paper: const Color(0xfffaf8fc),
      ink: const Color(0xff22212a),
    ),
    (
      name: 'dark',
      paper: const Color(0xff17151d),
      ink: const Color(0xffe8e1ee),
    ),
  ]) {
    testWidgets(
      'front stays clean and the opaque reverse is textured throughout: ${config.name}',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const shape = DiaryPaperShape(seed: 42);
        final front = await _paint(
          tester,
          shape: shape,
          paper: config.paper,
          ink: config.ink,
        );
        final back = await _paint(
          tester,
          shape: shape,
          paper: config.paper,
          ink: config.ink,
          reverse: true,
        );
        expect(
          _rimWear(back, config.paper),
          greaterThan(_rimWear(front, config.paper) * 1.2),
        );
        final color = config.paper.toARGB32();
        final textured = List.filled(4, 0);
        final sampled = List.filled(4, 0);
        // Small tears remove only the rim; both faces share that silhouette
        // while the remaining paper stays fully opaque.
        for (var offset = 3; offset < front.lengthInBytes; offset += 4) {
          final alpha = front.getUint8(offset);
          // Additional reverse grain can change partially covered edge pixels.
          if (alpha == 0 || alpha == 255) {
            expect(back.getUint8(offset), alpha);
          }
        }
        for (var y = 28; y < 392; y++) {
          for (var x = 28; x < 272; x++) {
            final offset = _offset(x, y);
            expect(front.getUint8(offset + 3), 255);
            expect(back.getUint8(offset + 3), 255);
            if (x > 40 && x < 260 && y > 40 && y < 380) {
              expect(front.getUint8(offset), (color >> 16) & 255);
              expect(front.getUint8(offset + 1), (color >> 8) & 255);
              expect(front.getUint8(offset + 2), color & 255);
              final quadrant = (x >= 150 ? 1 : 0) + (y >= 210 ? 2 : 0);
              sampled[quadrant]++;
              if ((back.getUint8(offset) - front.getUint8(offset)).abs() >= 3 ||
                  (back.getUint8(offset + 1) - front.getUint8(offset + 1))
                          .abs() >=
                      3 ||
                  (back.getUint8(offset + 2) - front.getUint8(offset + 2))
                          .abs() >=
                      3) {
                textured[quadrant]++;
              }
            }
          }
        }
        expect(front.getUint8(_offset(0, 0) + 3), 0);
        expect(back.getUint8(_offset(0, 0) + 3), 0);
        for (var quadrant = 0; quadrant < 4; quadrant++) {
          expect(textured[quadrant], greaterThan(sampled[quadrant] * .2));
        }
        final again = await _paint(
          tester,
          shape: shape,
          paper: config.paper,
          ink: config.ink,
        );
        expect(
          again.buffer.asUint8List(),
          orderedEquals(front.buffer.asUint8List()),
        );
        final backAgain = await _paint(
          tester,
          shape: shape,
          paper: config.paper,
          ink: config.ink,
          reverse: true,
        );
        expect(
          backAgain.buffer.asUint8List(),
          orderedEquals(back.buffer.asUint8List()),
        );
      },
    );

    testWidgets(
      'expansion removes all edge material and matches surface: ${config.name}',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final rest = await _paint(
          tester,
          shape: const DiaryPaperShape(seed: 42),
          paper: config.paper,
          ink: config.ink,
        );
        final half = await _paint(
          tester,
          shape: const DiaryPaperShape(seed: 42, expansion: .5),
          paper: config.paper,
          ink: config.ink,
        );
        expect(
          _rimWear(half, config.paper),
          lessThan(_rimWear(rest, config.paper)),
        );
        final expanded = await _paint(
          tester,
          shape: const DiaryPaperShape(seed: 42, expansion: 1),
          paper: config.paper,
          ink: config.ink,
        );
        final color = config.paper.toARGB32();
        for (var offset = 0; offset < expanded.lengthInBytes; offset += 4) {
          expect(expanded.getUint8(offset), (color >> 16) & 255);
          expect(expanded.getUint8(offset + 1), (color >> 8) & 255);
          expect(expanded.getUint8(offset + 2), color & 255);
          expect(expanded.getUint8(offset + 3), 255);
        }
      },
    );
  }
}
