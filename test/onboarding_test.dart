import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/root/views/pages/onboarding_page.dart';
import 'package:journal/modules/root/views/widgets/onboarding_book/book_materials.dart';
import 'package:journal/modules/root/views/widgets/onboarding_book/onboarding_book.dart';
import 'package:journal/modules/root/views/widgets/onboarding_btn.dart';
import 'package:journal/modules/root/views/widgets/onboarding_ink_background.dart';
import 'package:journal/utils/cache.dart';

class _Store implements KeyValueStore {
  final values = <String, Object>{};
  Completer<void>? pending;
  bool fail = false;
  int writes = 0;
  @override
  Object? get(String key) => values[key];
  @override
  bool containsKey(String key) => values.containsKey(key);
  @override
  Set<String> getKeys() => values.keys.toSet();
  @override
  Future<void> reload() async {}
  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> put(String key, Object value) async {
    writes++;
    if (fail) throw StateError('offline');
    await pending?.future;
    values[key] = value;
  }
}

void main() {
  final store = _Store();
  setUpAll(() async {
    await CacheStorage.init(store: store);
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      final loader = FontLoader('Georgia')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool reduced = false,
    double keyboard = 0,
    double pixelRatio = 2,
    EdgeInsets safePadding = EdgeInsets.zero,
  }) async {
    tester.view.physicalSize = size * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Georgia'),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: pixelRatio,
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
            viewInsets: EdgeInsets.only(bottom: keyboard),
            padding: keyboard > 0
                ? safePadding.copyWith(bottom: 0)
                : safePadding,
            viewPadding: safePadding,
          ),
          child: const RepaintBoundary(
            key: ValueKey('capture'),
            child: OnboardingPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    // Decode the real artwork before inspecting pixels, including when this
    // test runs on its own with an empty image cache.
    final context = tester.element(find.byType(OnboardingBook));
    final width = tester.getSize(find.byType(OnboardingBook)).width;
    final cacheWidth = onboardingImageCacheWidth(width, pixelRatio);
    await tester.runAsync(
      () => Future.wait([
        precacheImage(const AssetImage('assets/images/j.png'), context),
        precacheImage(const AssetImage(onboardingInkAsset), context),
        precacheImage(const AssetImage(onboardingCoverAsset), context),
        for (final provider in bookMaterialProviders)
          precacheImage(provider, context),
        for (final feature in onboardingFeatures)
          precacheImage(
            onboardingArtworkProvider(feature.artwork, cacheWidth),
            context,
          ),
      ]),
    );
    await tester.pump();
  }

  OnboardingBook book(WidgetTester tester) =>
      tester.widget<OnboardingBook>(find.byType(OnboardingBook));
  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Future<void> tapPage(WidgetTester tester, {required bool left}) async {
    final feature = onboardingFeatures[book(tester).page];
    final label = left
        ? '${feature.name}. ${feature.title.replaceAll('\n', ' ')} '
              '${feature.detail.replaceAll('\n', ' ')}'
        : feature.scene;
    final leaf = tester.renderObject<RenderBox>(find.bySemanticsLabel(label));
    // Near the hinge, the increased tilt moves each page across the screen's
    // center line. Hit testing must follow the paper, rather than screen halves.
    final point = left
        ? Offset(leaf.size.width - 7, leaf.size.height * .9)
        : Offset(7, leaf.size.height * .1);
    await tester.tapAt(leaf.localToGlobal(point));
  }

  Future<void> begin(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(OnboardingPrimaryButton));
    await tester.tap(find.byType(OnboardingPrimaryButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
  }

  testWidgets('artwork assets have book proportions and decode successfully', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final feature in onboardingFeatures) {
        final data = await rootBundle.load(feature.artwork);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width / frame.image.height, closeTo(4 / 3, .001));
        frame.image.dispose();
        codec.dispose();
      }
      final data = await rootBundle.load(onboardingCoverAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      expect(frame.image.width / frame.image.height, closeTo(4 / 5, .001));
      frame.image.dispose();
      codec.dispose();
      for (final asset in [bookPaperEdgeAsset, bookBindingAsset]) {
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(100));
        expect(frame.image.height, greaterThan(100));
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets(
    'open pages are images with accessible copy and fixed proportions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester, reduced: true);
        final normal = tester.getSize(find.byType(OnboardingBook));
        await stop(tester);
        await mount(tester, reduced: true, scale: 1.5);
        final size = tester.getSize(find.byType(OnboardingBook));
        expect(size.width, lessThanOrEqualTo(normal.width));
        expect(size.height, lessThanOrEqualTo(normal.height));
        expect((size.width - 12) / (size.height - 20), closeTo(4 / 3, .001));
        final rawImages = find.descendant(
          of: find.byType(OnboardingBook),
          matching: find.byType(RawImage),
        );
        expect(rawImages, findsNWidgets(2));
        for (final image in tester.widgetList<RawImage>(rawImages)) {
          expect(image.image, isNotNull);
        }
        expect(
          find.bySemanticsLabel(
            'Notes. Catch a thought. Little ideas. Endless possibilities.',
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(OnboardingBook),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
        await stop(tester);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('tour advances through all features and stops on Movies', (
    tester,
  ) async {
    await mount(tester);
    expect(book(tester).page, 0);
    for (var i = 1; i <= 5; i++) {
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(book(tester).page, i);
    }
    await tester.pump(const Duration(seconds: 20));
    expect(book(tester).page, 5);
    await stop(tester);
  });
  testWidgets(
    'swipes forward and backward without visible navigation controls',
    (tester) async {
      await mount(tester);
      await tester.drag(find.byType(OnboardingBook), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(book(tester).page, 1);
      await tester.drag(find.byType(OnboardingBook), const Offset(250, 0));
      await tester.pumpAndSettle();
      expect(book(tester).page, 0);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      await stop(tester);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'page taps curl in either direction, reduced motion: $reduced',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, reduced: reduced);
          await tapPage(tester, left: true);
          await tester.pumpAndSettle();
          expect(book(tester).page, 0);
          expect(book(tester).turn, 0);

          await tapPage(tester, left: false);
          await tester.pump();
          if (!reduced) {
            await tester.pump(const Duration(milliseconds: 100));
            expect(book(tester).direction, 1);
            expect(book(tester).turn, inExclusiveRange(0, 1));
            // Further taps during the curl cannot queue or interrupt another turn.
            final center = tester.getCenter(find.byType(OnboardingBook));
            await tester.tapAt(center + const Offset(80, 0));
            await tester.tapAt(center - const Offset(80, 0));
          }
          await tester.pumpAndSettle();
          expect(book(tester).page, 1);

          await tapPage(tester, left: true);
          await tester.pump();
          if (!reduced) {
            await tester.pump(const Duration(milliseconds: 100));
            expect(book(tester).direction, -1);
            expect(book(tester).turn, inExclusiveRange(0, 1));
          }
          await tester.pumpAndSettle();
          expect(book(tester).page, 0);

          for (var page = 1; page <= 5; page++) {
            await tapPage(tester, left: false);
            await tester.pumpAndSettle();
            expect(book(tester).page, page);
          }
          await tapPage(tester, left: false);
          await tester.pumpAndSettle();
          expect(book(tester).page, 5);
          expect(book(tester).turn, 0);
          await stop(tester);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('page taps wait for closing, naming and reopening to finish', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester);
      await tapPage(tester, left: false);
      await tester.pumpAndSettle();
      expect(book(tester).page, 1);
      tester
          .widget<OnboardingPrimaryButton>(find.byType(OnboardingPrimaryButton))
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(book(tester).onPageTap, isNull);
      await tapPage(tester, left: false);
      await tester.pumpAndSettle();
      expect(book(tester).page, 1);
      expect(book(tester).closing, 1);
      expect(book(tester).onPageTap, isNull);
      await tester.enterText(find.byType(TextField), 'Maya');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(book(tester).nameFocus.hasFocus, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(book(tester).onPageTap, isNull);
      await tapPage(tester, left: false);
      await tester.pumpAndSettle();
      expect(book(tester).page, 1);
      expect(book(tester).closing, 0);
      await tapPage(tester, left: false);
      await tester.pumpAndSettle();
      expect(book(tester).page, 2);
      await stop(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'Begin finishes a turn, closes book and focuses name; save validates and retries',
    (tester) async {
      await mount(tester);
      await tester.pump(const Duration(seconds: 5));
      await begin(tester);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(book(tester).closing, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      expect(
        tester
            .widget<OnboardingPrimaryButton>(
              find.byType(OnboardingPrimaryButton),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '   ');
      expect(
        tester
            .widget<OnboardingPrimaryButton>(
              find.byType(OnboardingPrimaryButton),
            )
            .onPressed,
        isNull,
      );
      store.fail = true;
      await tester.enterText(find.byType(TextField), '  Léwis 🌿  ');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        find.text('Couldn’t save your name. Please try again.'),
        findsOneWidget,
      );
      store.fail = false;
      store.pending = Completer<void>();
      final before = store.writes;
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(store.writes, before + 1);
      expect(
        tester
            .widget<OnboardingPrimaryButton>(
              find.byType(OnboardingPrimaryButton),
            )
            .onPressed,
        isNull,
      );
      await stop(tester);
      store.pending!.complete();
      await tester.pump();
      expect(CacheStorage.instance.get(userNameKey), 'Léwis 🌿');
      store.pending = null;
    },
  );
  testWidgets('reduced motion and lifecycle pause autoplay', (tester) async {
    await mount(tester, reduced: true);
    await tester.pump(const Duration(seconds: 20));
    expect(book(tester).page, 0);
    await stop(tester);
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 20));
    expect(book(tester).page, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(book(tester).page, 1);
    await stop(tester);
  });
  for (final size in [const Size(390, 844), const Size(768, 1024)]) {
    testWidgets('layout at $size and large text', (tester) async {
      await mount(tester, size: size, scale: 1.5, reduced: true);
      expect(tester.takeException(), isNull);
      await begin(tester);
      expect(tester.takeException(), isNull);
      await stop(tester);
    });
  }
  testWidgets('all spreads fit narrow screens with large text', (tester) async {
    await mount(tester, size: const Size(320, 568), scale: 1.5, reduced: true);
    for (var i = 0; i < 6; i++) {
      expect(book(tester).page, i);
      expect(tester.takeException(), isNull);
      if (i < 5) {
        await tester.ensureVisible(find.byType(OnboardingBook));
        await tester.drag(find.byType(OnboardingBook), const Offset(-250, 0));
        await tester.pumpAndSettle();
      }
    }
    await stop(tester);
  });

  testWidgets(
    'the layout keeps its footer and actions visible without scrolling',
    (tester) async {
      for (final layout in [
        (
          size: const Size(390, 844),
          scale: 1.0,
          padding: const EdgeInsets.only(top: 47, bottom: 34),
        ),
        (
          size: const Size(320, 568),
          scale: 1.5,
          padding: const EdgeInsets.only(top: 24, bottom: 16),
        ),
        (
          size: const Size(768, 1024),
          scale: 1.0,
          padding: const EdgeInsets.only(top: 24, bottom: 20),
        ),
        (size: const Size(844, 390), scale: 1.5, padding: EdgeInsets.zero),
      ]) {
        await mount(
          tester,
          size: layout.size,
          scale: layout.scale,
          safePadding: layout.padding,
          reduced: true,
        );
        final terms = find.byKey(const ValueKey('onboarding-terms'));
        final description = find.byKey(
          const ValueKey('onboarding-description'),
        );
        final button = find.byType(OnboardingPrimaryButton);
        final cover = find.byType(OnboardingBook);
        final footer = tester.getRect(terms);
        final action = tester.getRect(button);
        final bookBounds = tester.getRect(cover);
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(
          find.ancestor(of: cover, matching: find.byType(Scrollable)),
          findsNothing,
        );
        expect(
          footer.bottom,
          closeTo(layout.size.height - layout.padding.bottom, .1),
        );
        expect(action.bottom, lessThanOrEqualTo(footer.top));
        expect(button.hitTestable(), findsOneWidget);
        expect(
          action.top - tester.getRect(description).bottom,
          inInclusiveRange(16, 24),
        );
        if (layout.size.width < layout.size.height) {
          expect(
            bookBounds.bottom,
            lessThanOrEqualTo(tester.getRect(description).top),
          );
          final mascot = find.byKey(const ValueKey('onboarding-mascot'));
          if (layout.scale == 1) {
            expect(mascot, findsOneWidget);
            expect(
              tester.getRect(mascot).bottom,
              lessThanOrEqualTo(bookBounds.top),
            );
          }
        }
        await tester.drag(cover, const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(tester.getRect(terms), footer);
        expect(tester.getRect(button), action);
        expect(tester.getRect(cover), bookBounds);
        expect(tester.takeException(), isNull);
        await stop(tester);
      }
    },
  );

  testWidgets('pagination stays close to the book on taller screens', (
    tester,
  ) async {
    Size? bookSize;
    double? spacing;
    for (final height in [844.0, 1000.0, 1190.0]) {
      await mount(
        tester,
        size: Size(390, height),
        safePadding: const EdgeInsets.only(top: 47, bottom: 34),
        reduced: true,
      );
      final cover = find.byType(OnboardingBook);
      final pagination = find.byKey(const ValueKey('onboarding-page-hints'));
      final gap =
          tester.getTopLeft(pagination).dy - tester.getBottomRight(cover).dy;
      bookSize ??= tester.getSize(cover);
      spacing ??= gap;
      expect(tester.getSize(cover), bookSize);
      expect(gap, closeTo(spacing, .1));
      expect(gap, inInclusiveRange(8, 36));
      expect(
        tester.getBottomRight(pagination).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('onboarding-description')))
              .dy,
        ),
      );
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
      await stop(tester);
    }
  });

  testWidgets(
    'the name field and Save fit above the keyboard without scrolling',
    (tester) async {
      await mount(
        tester,
        keyboard: 300,
        safePadding: const EdgeInsets.only(top: 47, bottom: 34),
        reduced: true,
      );
      await begin(tester);
      await tester.enterText(find.byType(TextField), 'Maya');
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-terms')), findsNothing);
      expect(find.byKey(const ValueKey('onboarding-mascot')), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(
        find.byType(OnboardingPrimaryButton).hitTestable(),
        findsOneWidget,
      );
      for (final field in [
        find.byType(TextField),
        find.byType(OnboardingPrimaryButton),
      ]) {
        expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(544));
      }
      final cover = tester
          .renderObject<RenderTransform>(
            find.byKey(const ValueKey('book-cover-hinge')),
          )
          .child!;
      final coverBounds = MatrixUtils.transformRect(
        cover.getTransformTo(null),
        Offset.zero & cover.size,
      );
      final saveTop = tester
          .getTopLeft(find.byType(OnboardingPrimaryButton))
          .dy;
      expect(coverBounds.left, greaterThanOrEqualTo(0));
      expect(coverBounds.right, lessThanOrEqualTo(390));
      expect(coverBounds.top, greaterThanOrEqualTo(47));
      expect(coverBounds.bottom, lessThan(saveTop));
      expect(coverBounds.height, greaterThan((saveTop - 47) * .8));
      expect(tester.takeException(), isNull);
      await stop(tester);
    },
  );
  testWidgets(
    'closed journal stays framed and keeps its image as the keyboard resizes',
    (tester) async {
      for (final size in [const Size(390, 844), const Size(768, 1024)]) {
        await mount(tester, size: size, keyboard: 300, reduced: true);
        await begin(tester);
        await tester.enterText(find.byType(TextField), 'Maya');
        await tester.pump();
        final image = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image == const AssetImage(onboardingCoverAsset),
        );
        final raw = find.descendant(of: image, matching: find.byType(RawImage));
        final decodedCover = tester.widget<RawImage>(raw).image;
        expect(decodedCover, isNotNull);
        for (final keyboard in [0.0, 120.0, 250.0, 300.0, 0.0]) {
          await mount(tester, size: size, keyboard: keyboard, reduced: true);
          final cover = tester
              .renderObject<RenderTransform>(
                find.byKey(const ValueKey('book-cover-hinge')),
              )
              .child!;
          final bounds = MatrixUtils.transformRect(
            cover.getTransformTo(null),
            Offset.zero & cover.size,
          );
          expect(bounds.left, greaterThanOrEqualTo(size.width * .1));
          expect(bounds.right, lessThanOrEqualTo(size.width * .9));
          expect(bounds.width, lessThanOrEqualTo(370));
          expect(
            bounds.bottom,
            lessThan(
              tester.getTopLeft(find.byType(OnboardingPrimaryButton)).dy,
            ),
          );
          expect(tester.widget<RawImage>(raw).image, same(decodedCover));
          expect(find.byType(TextField).hitTestable(), findsOneWidget);
          expect(book(tester).nameController.text, 'Maya');
          expect(tester.takeException(), isNull);
        }
        await stop(tester);
      }
    },
  );
  testWidgets(
    'back dismisses focus then returns to paused tour with draft intact',
    (tester) async {
      await mount(tester, reduced: true);
      await begin(tester);
      await tester.enterText(find.byType(TextField), 'Maya');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(book(tester).closing, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(book(tester).closing, 0);
      await tester.pump(const Duration(seconds: 20));
      expect(book(tester).page, 0);
      await begin(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Maya',
      );
      await stop(tester);
    },
  );
  testWidgets('obscuring route pauses the tour', (tester) async {
    await mount(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(book(tester).page, 0);
    await stop(tester);
  });
  testWidgets('Back opens the cover gradually and keeps the name draft', (
    tester,
  ) async {
    await mount(tester);
    await begin(tester);
    await tester.enterText(find.byType(TextField), 'Maya');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(book(tester).closing, 1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(book(tester).closing, inExclusiveRange(0, 1));
    expect(book(tester).editable, isFalse);
    expect(
      tester
          .widget<OnboardingPrimaryButton>(find.byType(OnboardingPrimaryButton))
          .onPressed,
      isNull,
    );
    await tester.drag(find.byType(OnboardingBook), const Offset(-250, 0));
    expect(book(tester).page, 0);
    await tester.pumpAndSettle();
    expect(book(tester).closing, 0);
    await tester.pump(const Duration(seconds: 20));
    expect(book(tester).page, 0);
    await begin(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Maya',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    await stop(tester);
  });

  testWidgets('disposing during reopening cancels the fold cleanly', (
    tester,
  ) async {
    await mount(tester);
    await begin(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(book(tester).closing, inExclusiveRange(0, 1));
    await stop(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tilted case and lifted cover fit phone and tablet screens', (
    tester,
  ) async {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      await mount(tester, size: size);
      Rect? sweep;
      void include(Offset point) {
        final bounds = Rect.fromPoints(point, point);
        sweep = sweep?.expandToInclude(bounds) ?? bounds;
      }

      final back = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('book-stationary-case')),
      );
      for (final corner in [
        const Offset(-3, 7),
        Offset(back.size.width + 3, 7),
        Offset(-3, back.size.height - 2),
        Offset(back.size.width + 3, back.size.height - 2),
      ]) {
        include(back.localToGlobal(corner));
      }
      tester
          .widget<OnboardingPrimaryButton>(find.byType(OnboardingPrimaryButton))
          .onPressed!();
      await tester.pump();
      for (var frame = 0; frame <= 22; frame++) {
        final hinge = tester.renderObject<RenderTransform>(
          find.byKey(const ValueKey('book-cover-hinge')),
        );
        final cover = hinge.child!;
        for (final corner in [
          Offset.zero,
          Offset(cover.size.width, 0),
          Offset(0, cover.size.height),
          Offset(cover.size.width, cover.size.height),
        ]) {
          include(cover.localToGlobal(corner));
        }
        if (frame < 22) await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sweep!.left, greaterThanOrEqualTo(0), reason: '$size: $sweep');
      expect(
        sweep!.right,
        lessThanOrEqualTo(size.width),
        reason: '$size: $sweep',
      );
      expect(sweep!.top, greaterThanOrEqualTo(0), reason: '$size: $sweep');
      expect(
        sweep!.bottom,
        lessThanOrEqualTo(size.height),
        reason: '$size: $sweep',
      );
      await stop(tester);
    }
  });

  testWidgets('the back case stays anchored while closing and reopening', (
    tester,
  ) async {
    await mount(tester);
    List<double> backTransform() => tester
        .renderObject<RenderBox>(
          find.byKey(const ValueKey('book-stationary-case')),
        )
        .getTransformTo(null)
        .storage
        .toList();
    final openTransform = backTransform();
    Future<void> checkFold() async {
      for (var frame = 0; frame <= 22; frame++) {
        if (book(tester).closing <= .8) {
          final current = backTransform();
          for (var i = 0; i < current.length; i++) {
            expect(
              current[i],
              closeTo(openTransform[i], .000001),
              reason: 'the back case moved during the fold at frame $frame',
            );
          }
        }
        if (frame < 22) await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    tester
        .widget<OnboardingPrimaryButton>(find.byType(OnboardingPrimaryButton))
        .onPressed!();
    await tester.pump();
    await checkFold();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await checkFold();
    expect(book(tester).closing, 0);
    await stop(tester);
  });

  testWidgets('visual captures and keyboard layout', (tester) async {
    await mount(tester);
    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('ONBOARDING_CAPTURES')) return;
      await tester.pump();
      final journal = book(tester);
      final cacheWidth = onboardingImageCacheWidth(
        journal.artworkWidth ??
            tester.getSize(find.byType(OnboardingBook)).width,
        2,
      );
      final context = tester.element(find.byType(OnboardingBook));
      await tester.runAsync(
        () => Future.wait([
          precacheImage(const AssetImage(onboardingCoverAsset), context),
          precacheImage(
            onboardingArtworkProvider(
              onboardingFeatures[journal.page].artwork,
              cacheWidth,
            ),
            context,
          ),
        ]),
      );
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/journal-$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('open');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(OnboardingBook)) + const Offset(100, 0),
    );
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    await capture('bend');
    await gesture.moveBy(const Offset(-70, 0));
    await tester.pump();
    await capture('bend-back');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(book(tester).page, 1);
    final reverseGesture = await tester.startGesture(
      tester.getCenter(find.byType(OnboardingBook)) - const Offset(100, 0),
    );
    // Stay below the commit threshold when the pointer is canceled.
    await reverseGesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await capture('reverse-bend');
    await reverseGesture.cancel();
    await tester.pumpAndSettle();
    expect(book(tester).page, 1);
    await capture('diary');
    for (final name in ['ai', 'tasks', 'birthdays', 'movies']) {
      await tester.drag(find.byType(OnboardingBook), const Offset(-250, 0));
      await tester.pumpAndSettle();
      await capture(name);
    }
    await tester.ensureVisible(find.byType(OnboardingPrimaryButton));
    await tester.tap(find.byType(OnboardingPrimaryButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await capture('closing-front');
    await tester.pump(const Duration(milliseconds: 350));
    await capture('closing-back');
    await tester.pumpAndSettle();
    await capture('cover');
    if (const bool.fromEnvironment('ONBOARDING_MOTION_CAPTURES')) {
      await tester.enterText(find.byType(TextField), 'Maya');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      for (var i = 0; i <= 22; i++) {
        await capture('opening-${i.toString().padLeft(2, '0')}');
        if (i < 22) await tester.pump(const Duration(milliseconds: 50));
      }
      expect(book(tester).closing, 0);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OnboardingPrimaryButton>(
              find.byType(OnboardingPrimaryButton),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byType(OnboardingPrimaryButton));
      await tester.pump();
      for (var i = 0; i <= 22; i++) {
        await capture('closing-${i.toString().padLeft(2, '0')}');
        if (i < 22) await tester.pump(const Duration(milliseconds: 50));
      }
      expect(book(tester).closing, 1);
    }
    await stop(tester);
    await mount(tester, keyboard: 300, reduced: true);
    await begin(tester);
    await capture('keyboard');
    expect(tester.takeException(), isNull);
    await stop(tester);
    await mount(tester, size: const Size(320, 568), scale: 1.5, reduced: true);
    await capture('narrow-large-text');
    await stop(tester);
    await mount(tester, size: const Size(768, 1024), reduced: true);
    await capture('tablet');
    await stop(tester);
    await mount(
      tester,
      safePadding: const EdgeInsets.only(top: 47, bottom: 34),
      reduced: true,
    );
    await capture('safe-phone');
    await stop(tester);
    await mount(tester, size: const Size(844, 390), scale: 1.5, reduced: true);
    await capture('landscape');
    await stop(tester);
  });
}
