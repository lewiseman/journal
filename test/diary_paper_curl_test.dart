import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_curl.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';

void main() {
  for (final direction in [-1, 1]) {
    testWidgets('curl exposes paper back and clears the viewport: $direction', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const capture = ValueKey('curl-capture');

      Future<({int front, int back, ByteData data})> pixels(
        double progress, {
        bool transparentFront = false,
        Color background = Colors.white,
      }) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: background,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 310,
                        top: 70,
                        width: 280,
                        height: 260,
                        child: DiaryPaperCurl(
                          progress: progress,
                          direction: direction,
                          travel: 700,
                          paper: Colors.blue,
                          ink: Colors.black,
                          child: ClipPath(
                            clipper: const DiaryPaperClipper(DiaryPaperShape()),
                            child: ColoredBox(
                              color: transparentFront
                                  ? Colors.transparent
                                  : Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final data = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes;
        }))!;
        int front = 0;
        int back = 0;
        for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
          final r = data.getUint8(offset);
          final g = data.getUint8(offset + 1);
          final b = data.getUint8(offset + 2);
          if (r > 170 && g < 90 && b < 90) front++;
          if (b > 150 && r < 100 && g < 160) back++;
        }
        expect(tester.takeException(), isNull);
        return (front: front, back: back, data: data);
      }

      final flat = await pixels(0);
      expect(flat.front, greaterThan(60000));
      expect(flat.back, 0);
      final curled = await pixels(.4);
      expect(curled.front, greaterThan(1000));
      expect(curled.back, greaterThan(500));
      // The reverse must supply its own opaque paper, independently of any
      // transparent areas or widgets in the front texture.
      final transparent = await pixels(.4, transparentFront: true);
      expect(transparent.back, greaterThanOrEqualTo(curled.back * .95));
      final green = await pixels(
        .4,
        transparentFront: true,
        background: Colors.green,
      );
      bool isBack(int x, int y) {
        final offset = (y * 900 + x) * 4;
        return curled.data.getUint8(offset) < 100 &&
            curled.data.getUint8(offset + 1) < 160 &&
            curled.data.getUint8(offset + 2) > 150;
      }

      bool isBackInterior(int x, int y) {
        // Include diagonals: a deep, slanted tear can pass between the four
        // cardinal samples. Only compare fully covered material, excluding
        // antialiased pixels where the torn edge reveals what is underneath.
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            if (!isBack(x + dx, y + dy)) return false;
          }
        }
        return true;
      }

      int checked = 0;
      for (var y = 2; y < 398; y++) {
        for (var x = 2; x < 898; x++) {
          if (!isBackInterior(x, y)) continue;
          final offset = (y * 900 + x) * 4;
          for (var channel = 0; channel < 3; channel++) {
            // Its own aged material must be identical over different widgets
            // and different backgrounds, rather than merely look solid blue.
            expect(
              transparent.data.getUint8(offset + channel),
              closeTo(curled.data.getUint8(offset + channel), 1),
            );
            expect(
              green.data.getUint8(offset + channel),
              closeTo(curled.data.getUint8(offset + channel), 1),
            );
          }
          checked++;
        }
      }
      expect(checked, greaterThan(500));
      final gone = await pixels(1);
      expect(gone.front, 0);
      expect(gone.back, 0);
    });
  }
}
