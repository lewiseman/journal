import 'package:flutter/material.dart';

const onboardingInkAsset = 'assets/images/onboarding/ink-paper.webp';

/// Aged paper with faint dried ink drops, isolated from the book's repaints.
class OnboardingInkBackground extends StatelessWidget {
  const OnboardingInkBackground({super.key});

  static const baseColor = Color(0xFFF2E7D2);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: ColoredBox(
          color: baseColor,
          child: Image.asset(
            onboardingInkAsset,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            // Keep the small margin drops visible on tall phone screens.
            alignment: Alignment.centerRight,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
