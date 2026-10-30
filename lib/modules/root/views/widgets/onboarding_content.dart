import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:journal/config/theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'onboarding_book/onboarding_book.dart';
import 'onboarding_btn.dart';
import 'onboarding_ink_background.dart';

/// The responsive onboarding view. The page owns workflow and interactions.
class OnboardingContent extends StatefulWidget {
  const OnboardingContent({
    super.key,
    required this.page,
    required this.direction,
    required this.turn,
    required this.close,
    required this.turning,
    required this.touring,
    required this.naming,
    required this.saving,
    required this.nameController,
    required this.nameFocus,
    required this.onBegin,
    required this.onSave,
    required this.onFlip,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    this.error,
  });

  final int page;
  final int direction;
  final Animation<double> turn;
  final Animation<double> close;
  final bool turning;
  final bool touring;
  final bool naming;
  final bool saving;
  final TextEditingController nameController;
  final FocusNode nameFocus;
  final String? error;
  final VoidCallback onBegin;
  final VoidCallback onSave;
  final ValueChanged<int> onFlip;
  final VoidCallback onDragStart;
  final void Function(double delta, double width) onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onDragCancel;

  @override
  State<OnboardingContent> createState() => _OnboardingContentState();
}

class _OnboardingContentState extends State<OnboardingContent> {
  int? _artworkCacheWidth;

  void _precacheArtwork(double width) {
    final cacheWidth = onboardingImageCacheWidth(
      width,
      MediaQuery.devicePixelRatioOf(context),
    );
    if (_artworkCacheWidth == cacheWidth) return;
    _artworkCacheWidth = cacheWidth;
    // Warm every chapter and the cover so an immediate swipe or Begin does
    // not have to start decoding its destination artwork during the turn.
    unawaited(precacheImage(const AssetImage(onboardingCoverAsset), context));
    for (final feature in onboardingFeatures) {
      unawaited(
        precacheImage(
          onboardingArtworkProvider(feature.artwork, cacheWidth),
          context,
        ),
      );
    }
  }

  Widget _buildBook({
    required double width,
    required double height,
    required double artworkWidth,
    required bool naming,
    required bool touring,
  }) => AnimatedBuilder(
    animation: Listenable.merge([widget.turn, widget.close]),
    builder: (context, _) => Semantics(
      label: naming
          ? 'Your journal cover'
          : '${onboardingFeatures[widget.page].name}, ${widget.page + 1} of ${onboardingFeatures.length}',
      onIncrease: touring && widget.page < onboardingFeatures.length - 1
          ? () => widget.onFlip(1)
          : null,
      onDecrease: touring && widget.page > 0 ? () => widget.onFlip(-1) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.touring && !widget.turning
            ? (_) => widget.onDragStart()
            : null,
        onHorizontalDragUpdate: (details) =>
            widget.onDragUpdate(details.delta.dx, width),
        onHorizontalDragEnd: (details) =>
            widget.onDragEnd(details.velocity.pixelsPerSecond.dx),
        onHorizontalDragCancel: widget.onDragCancel,
        child: SizedBox(
          width: width,
          height: height,
          child: OnboardingBook(
            artworkWidth: artworkWidth,
            page: widget.page,
            direction: widget.direction,
            turn: widget.turning ? widget.turn.value : 0,
            closing: widget.close.value,
            nameController: widget.nameController,
            nameFocus: widget.nameFocus,
            editable: naming && !widget.saving,
            onSubmit: widget.onSave,
            onPageTap: touring && !widget.turning ? widget.onFlip : null,
          ),
        ),
      ),
    ),
  );

  Widget _buildPresentation({
    required bool naming,
    required bool touring,
  }) => AnimatedBuilder(
    animation: widget.close,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 260;
        final showMascot = !naming && constraints.maxHeight >= 200;
        final mascotHeight = math.min(100.0, constraints.maxHeight * .18);
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showMascot) ...[
                  Image.asset(
                    'assets/images/j.png',
                    key: const ValueKey('onboarding-mascot'),
                    height: mascotHeight,
                    excludeFromSemantics: true,
                  ),
                  // Keep the logo with the book as the viewport grows.
                  const SizedBox(height: 8),
                ],
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, bookConstraints) {
                      final settled = Curves.easeInOutCubic.transform(
                        ((widget.close.value - .8) / .2).clamp(0.0, 1.0),
                      );
                      // Release the tilt and lift margins once the cover closes.
                      final framing = 1 - settled;
                      final maxHeight =
                          (bookConstraints.maxHeight - 12) /
                          (1 + .12 * framing);
                      if (maxHeight < 48) return const SizedBox.shrink();
                      final openWidth = math.min(
                        math.min(bookConstraints.maxWidth - 24, 720.0),
                        ((bookConstraints.maxHeight - 12) / 1.12 - 20) *
                                onboardingSpreadAspectRatio +
                            12,
                      );
                      // A closed journal occupies one leaf, so it can use twice
                      // the spread width. Grow only after the cover has folded,
                      // matching the book's final settling phase.
                      final closedWidth = math.min(
                        // Keep the portrait cover comfortably framed even
                        // when dismissing the keyboard frees a lot of height.
                        math.min(bookConstraints.maxWidth * .72, 360.0) * 2 +
                            12,
                        (bookConstraints.maxHeight - 32) *
                                onboardingSpreadAspectRatio +
                            12,
                      );
                      final width = math.min(
                        openWidth + (closedWidth - openWidth) * settled,
                        (maxHeight - 20) * onboardingSpreadAspectRatio + 12,
                      );
                      final height =
                          (width - 12) / onboardingSpreadAspectRatio + 20;
                      // Decode once at the destination size rather than at
                      // every intermediate width during the settling animation.
                      final artworkWidth = widget.close.value == 0
                          ? openWidth
                          : closedWidth;
                      _precacheArtwork(artworkWidth);
                      return Padding(
                        padding: EdgeInsets.only(
                          top: height * .04 * framing + 4,
                          bottom: height * .08 * framing + 8,
                        ),
                        child: SizedBox(
                          width: math.min(width, bookConstraints.maxWidth),
                          height: height,
                          child: OverflowBox(
                            minWidth: width,
                            maxWidth: width,
                            minHeight: height,
                            maxHeight: height,
                            child: _buildBook(
                              width: width,
                              height: height,
                              artworkWidth: artworkWidth,
                              naming: naming,
                              touring: touring,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!naming)
                  _OnboardingPageHints(page: widget.page, compact: compact),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _buildActions({required bool naming, required bool keyboard}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          key: const ValueKey('onboarding-actions'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!naming)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: const Text(
                  'Your space for notes, diary and passing thoughts, with local AI support.',
                  key: ValueKey('onboarding-description'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF514354),
                    fontSize: 18,
                    height: 1.45,
                    letterSpacing: -.2,
                  ),
                ),
              )
            else if (!keyboard)
              Text(
                'Your story starts with you.',
                textAlign: TextAlign.center,
                style: GoogleFontsLite.getFont(
                  'Allura',
                  color: const Color(0xFF433548),
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  widget.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF9B3E4C)),
                ),
              ),
            if (!naming || !keyboard || widget.error != null)
              const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: OnboardingPrimaryButton(
                label: naming
                    ? (widget.saving ? 'Saving…' : 'Save')
                    : "Let's begin",
                onPressed: naming
                    ? (!widget.saving &&
                              widget.nameController.text.trim().isNotEmpty
                          ? widget.onSave
                          : null)
                    : (widget.touring ? widget.onBegin : null),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final naming = widget.naming;
    final touring = widget.touring;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppThemeConfig.lightSystemUiOverlay.copyWith(
        systemNavigationBarColor: OnboardingInkBackground.baseColor,
      ),
      child: Scaffold(
        backgroundColor: OnboardingInkBackground.baseColor,
        body: Stack(
          children: [
            const Positioned.fill(child: OnboardingInkBackground()),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide =
                            constraints.maxWidth > 600 &&
                            constraints.maxWidth > constraints.maxHeight * 1.4;
                        final presentation = _buildPresentation(
                          naming: naming,
                          touring: touring,
                        );
                        final actions = _buildActions(
                          naming: naming,
                          keyboard: keyboard,
                        );
                        if (wide) {
                          return Row(
                            children: [
                              Expanded(child: presentation),
                              Expanded(child: actions),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            Expanded(child: presentation),
                            actions,
                          ],
                        );
                      },
                    ),
                  ),
                  if (!keyboard) const _OnboardingTerms(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageHints extends StatelessWidget {
  const _OnboardingPageHints({required this.page, required this.compact});

  final int page;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('onboarding-page-hints'),
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          onboardingFeatures.length,
          (i) => AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == page ? 22 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == page
                  ? const Color(0xFF715B83)
                  : const Color(0xFFA99A91),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      if (!compact) ...[
        const SizedBox(height: 10),
        const Text(
          'Tap a page or swipe to turn.',
          style: TextStyle(color: Color(0xFF6B5E70), fontSize: 12, height: 1.2),
        ),
      ],
    ],
  );
}

class _OnboardingTerms extends StatefulWidget {
  const _OnboardingTerms();

  @override
  State<_OnboardingTerms> createState() => _OnboardingTermsState();
}

class _OnboardingTermsState extends State<_OnboardingTerms> {
  late final _terms = TapGestureRecognizer()
    ..onTap = () =>
        unawaited(_openLink('https://journal.lewiseman.com/terms.html'));
  late final _privacy = TapGestureRecognizer()
    ..onTap = () =>
        unawaited(_openLink('https://journal.lewiseman.com/privacy.html'));

  Future<void> _openLink(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Report launch failures below, including platform errors.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open this page. Please try again.'),
      ),
    );
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('onboarding-terms'),
    padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text.rich(
          TextSpan(
            text: 'By continuing. You agree to our ',
            style: const TextStyle(color: Color(0xFF6B5E70), height: 1.4),
            children: [
              TextSpan(
                text: 'Terms',
                recognizer: _terms,
                style: const TextStyle(
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF6B5E70),
                ),
              ),
              const TextSpan(text: " and you've read the "),
              TextSpan(
                text: 'Privacy policy',
                recognizer: _privacy,
                style: const TextStyle(
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF6B5E70),
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
