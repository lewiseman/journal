import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/root/views/widgets/onboarding_book/book_fold.dart';

void main() {
  for (final size in [const Size(142, 213), const Size(354, 531)]) {
    test('the case only recenters after the fold is complete at $size', () {
      for (final t in [0.0, .1, .4, .6, .79, .8]) {
        final fold = BookFoldGeometry(leafSize: size, progress: t);
        expect(fold.settleProgress, 0);
        expect(fold.recenter, 0);
      }
      for (final t in [.8, .85, .9, 1.0]) {
        final fold = BookFoldGeometry(leafSize: size, progress: t);
        expect(fold.foldProgress, 1);
      }
    });

    test(
      'front cover has a fixed hinge and lifts toward the viewer at $size',
      () {
        for (final t in [0.0, .1, .25, .5, .75, .9, 1.0]) {
          final fold = BookFoldGeometry(leafSize: size, progress: t);
          for (final y in [0.0, size.height / 2, size.height]) {
            final hinge = MatrixUtils.transformPoint(
              fold.transform,
              Offset(size.width, y),
            );
            expect(hinge.dx, closeTo(size.width, .00001));
            expect(hinge.dy, closeTo(y, .00001));
          }
          if (fold.foldProgress > 0 && fold.foldProgress < 1) {
            // The free edge's Z coordinate must approach the camera, whose
            // perspective plane is on negative Z, while the cover lifts.
            expect(fold.transform.storage[14], lessThan(0));
          }
        }
        final quarter = BookFoldGeometry(leafSize: size, progress: .25);
        final threeQuarter = BookFoldGeometry(leafSize: size, progress: .75);
        expect(
          MatrixUtils.transformPoint(quarter.transform, Offset.zero).dx,
          inExclusiveRange(0, size.width),
        );
        expect(
          MatrixUtils.transformPoint(threeQuarter.transform, Offset.zero).dx,
          greaterThan(size.width),
        );
      },
    );

    test(
      'closed cover matches the right leaf without mirrored artwork at $size',
      () {
        final fold = BookFoldGeometry(leafSize: size, progress: 1);
        final topLeft = MatrixUtils.transformPoint(
          fold.visibleFaceTransform,
          Offset.zero,
        );
        final bottomRight = MatrixUtils.transformPoint(
          fold.visibleFaceTransform,
          Offset(size.width, size.height),
        );
        expect(topLeft.dx, closeTo(size.width, .00001));
        expect(topLeft.dy, closeTo(0, .00001));
        expect(bottomRight.dx, closeTo(2 * size.width, .00001));
        expect(bottomRight.dy, closeTo(size.height, .00001));
        expect(fold.recenter, closeTo(-size.width / 2, .00001));
      },
    );

    test(
      'recentering keeps the fold within its six pixel edge inset at $size',
      () {
        for (var step = 0; step <= 100; step++) {
          final fold = BookFoldGeometry(leafSize: size, progress: step / 100);
          final tip = MatrixUtils.transformPoint(
            fold.transform,
            Offset(0, size.height / 2),
          ).dx;
          expect(tip + fold.recenter, greaterThanOrEqualTo(-6));
          expect(tip + fold.recenter, lessThanOrEqualTo(size.width * 2 + 6));
          expect(
            size.width * 2 + fold.recenter,
            lessThanOrEqualTo(size.width * 2 + 6),
          );
        }
      },
    );
  }
}
