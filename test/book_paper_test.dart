import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/root/views/widgets/onboarding_book/book_paper.dart';

void main() {
  testWidgets(
    'the open case has one continuous rim and an exposed cloth joint',
    (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 16, 16),
        Paint()..color = const Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      final binding = (await tester.runAsync(() => picture.toImage(16, 16)))!;
      picture.dispose();
      addTearDown(binding.dispose);
      const capture = ValueKey('case');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: capture,
              child: SizedBox(
                width: 360,
                height: 320,
                child: ColoredBox(
                  color: Colors.white,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned(
                        left: 0,
                        top: 0,
                        width: 360,
                        height: 290,
                        child: CustomPaint(painter: BookBoards()),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        width: 360,
                        height: 290,
                        child: CustomPaint(
                          painter: BookBinding(
                            progress: 0,
                            showLeft: false,
                            bindingTexture: binding,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 4,
                        width: 180,
                        height: 270,
                        child: CustomPaint(
                          painter: BookLeafStack(
                            left: true,
                            depth: 9,
                            board: true,
                            bindingTexture: binding,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final pixels = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return bytes;
      }))!;
      // The rim has no rounded inner corner, gap, or restarted lighting where
      // the two halves meet. It reads as a single strip beneath the paper.
      final reference = (286 * 360 + 180) * 4;
      for (var x = 177; x <= 183; x++) {
        final pixel = (286 * 360 + x) * 4;
        for (var channel = 0; channel < 3; channel++) {
          expect(
            (pixels.getUint8(pixel + channel) -
                    pixels.getUint8(reference + channel))
                .abs(),
            lessThanOrEqualTo(3),
            reason: 'rim discontinuity at x=$x',
          );
        }
      }
      // An identifiable red material must be visible on BOTH sides of the
      // hinge; neither the board nor the paper stack may cover that detail.
      for (final x in [179, 180]) {
        final pixel = (130 * 360 + x) * 4;
        expect(pixels.getUint8(pixel), greaterThan(150));
        expect(pixels.getUint8(pixel + 1), lessThan(40));
        expect(pixels.getUint8(pixel + 2), lessThan(40));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the closed back board and binding share a rounded spine corner',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(360, 290);
      const BookBoards(closing: 1).paint(canvas, size);
      const BookBinding(
        progress: 0,
        closing: 1,
        showLeft: false,
      ).paint(canvas, size);
      final picture = recorder.endRecording();
      final pixels = (await tester.runAsync(() async {
        final image = await picture.toImage(360, 320);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return bytes;
      }))!;
      picture.dispose();

      int alpha(int x, int y) => pixels.getUint8((y * 360 + x) * 4 + 3);
      // These points used to contain the opaque square rear corner or the
      // protruding cloth tab. Only a soft shadow belongs outside the curve.
      for (final (x, y) in [(180, 283), (181, 286), (183, 289)]) {
        expect(alpha(x, y), lessThan(160), reason: 'square corner at ($x, $y)');
      }
      // Rounding must leave both the upright spine and bottom rim intact.
      expect(alpha(181, 265), 255);
      expect(alpha(193, 286), 255);
    },
  );

  for (final reverse in [false, true]) {
    testWidgets('turn shadow stays on the receiving pages, reverse: $reverse', (
      tester,
    ) async {
      const capture = ValueKey('shadow');
      Future<int> shadowPixels(double progress) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: capture,
                child: SizedBox(
                  width: 420,
                  height: 300,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: reverse ? 50 : 210,
                          top: 50,
                          width: 160,
                          height: 200,
                          child: BentBookPage(
                            progress: progress,
                            reverse: reverse,
                            front: const ColoredBox(color: Colors.red),
                            back: const ColoredBox(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
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
        // Shadows cannot spill beyond the receiving book's outer edges.
        for (final x in [40, 380]) {
          final pixel = (150 * 420 + x) * 4;
          expect(data.getUint8(pixel), 255);
          expect(data.getUint8(pixel + 1), 255);
          expect(data.getUint8(pixel + 2), 255);
        }
        var count = 0;
        for (var y = 60; y < 240; y++) {
          for (var x = 50; x < 370; x++) {
            final pixel = (y * 420 + x) * 4;
            final r = data.getUint8(pixel);
            final g = data.getUint8(pixel + 1);
            final b = data.getUint8(pixel + 2);
            // Warm gray on the white receiver, excluding the colored faces.
            if (r > 100 && r < 250 && (r - g).abs() < 8 && (r - b).abs() < 8) {
              count++;
            }
          }
        }
        expect(tester.takeException(), isNull);
        return count;
      }

      expect(await shadowPixels(0), 0);
      expect(await shadowPixels(reverse ? .65 : .35), greaterThan(100));
      expect(await shadowPixels(1), 0);
    });

    testWidgets('curl reveals the back locally, reverse: $reverse', (
      tester,
    ) async {
      const capture = ValueKey('paper');
      Future<(int, int)> faces(double progress) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: capture,
                child: SizedBox(
                  width: 420,
                  height: 300,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: reverse ? 50 : 210,
                        top: 50,
                        width: 160,
                        height: 200,
                        child: BentBookPage(
                          progress: progress,
                          reverse: reverse,
                          front: const ColoredBox(color: Colors.red),
                          back: const ColoredBox(color: Colors.blue),
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
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data;
        }))!;
        int front = 0, back = 0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          final r = data.getUint8(i), b = data.getUint8(i + 2);
          if (r > 80 && r > b * 2) front++;
          if (b > 80 && b > r * 2) back++;
        }
        expect(tester.takeException(), isNull);
        return (front, back);
      }

      final open = await faces(0);
      expect(open.$1, greaterThan(20000));
      expect(open.$2, 0);
      final curled = await faces(.45);
      expect(curled.$1, greaterThan(100));
      expect(curled.$2, greaterThan(100));
      final turned = await faces(1);
      expect(turned.$1, 0);
      expect(turned.$2, greaterThan(20000));
    });
  }
}
