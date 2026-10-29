import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/settings/controllers/settings_ctrl.dart';

/// The local appearance preference controls motion for routes and overlays.
/// Other accessibility and display information keeps its platform value.
class AppMotionScope extends ConsumerWidget {
  const AppMotionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsController.select((settings) => settings.animationsEnabled),
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: !enabled),
      child: child,
    );
  }
}

/// Keeps each platform's navigation gestures while reducing route movement.
class AppPageTransitionsTheme extends PageTransitionsTheme {
  const AppPageTransitionsTheme();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context) &&
        !route.popGestureInProgress) {
      // Keep the platform's gesture detector, but show each transition's
      // destination immediately. Interactive back gestures still follow touch.
      animation = AlwaysStoppedAnimation(
        animation.status == AnimationStatus.reverse ? 0 : 1,
      );
      secondaryAnimation = AlwaysStoppedAnimation(
        secondaryAnimation.status == AnimationStatus.forward ||
                secondaryAnimation.status == AnimationStatus.completed
            ? 1
            : 0,
      );
    }
    return super.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
