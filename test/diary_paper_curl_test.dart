import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_curl.dart';

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

      Future<({int front, int back, int solidBack})> pixels(
        double progress, {
        bool transparentFront = false,
      }) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: Colors.white,
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
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
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
        int solidBack = 0;
        for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
          final r = data.getUint8(offset);
          final g = data.getUint8(offset + 1);
          final b = data.getUint8(offset + 2);
          if (r > 170 && g < 90 && b < 90) front++;
          if (b > 150 && r < 100 && g < 160) back++;
          if (r == 33 && g == 150 && b == 243) solidBack++;
        }
        expect(tester.takeException(), isNull);
        return (front: front, back: back, solidBack: solidBack);
      }

      final flat = await pixels(0);
      expect(flat.front, greaterThan(60000));
      expect(flat.back, 0);
      final curled = await pixels(.4);
      expect(curled.front, greaterThan(1000));
      expect(curled.back, greaterThan(500));
      expect(curled.solidBack, greaterThan(curled.back * .95));
      // The reverse must supply its own opaque paper, independently of any
      // transparent areas or widgets in the front texture.
      final transparent = await pixels(.4, transparentFront: true);
      expect(transparent.back, greaterThanOrEqualTo(curled.back * .95));
      expect(transparent.solidBack, greaterThan(transparent.back * .95));
      final gone = await pixels(1);
      expect(gone.front, 0);
      expect(gone.back, 0);
    });
  }
}
