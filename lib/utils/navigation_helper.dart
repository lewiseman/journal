import 'package:flutter/material.dart';

/// Built-in transitions; [platform] keeps Flutter's native page behavior.
enum NavTransition {
  platform,
  fade,
  fromRight,
  fromLeft,
  fromBottom,
  scale,
  fadeScale,
  fadeSlideUp,
  none,
}

/// A small, dependency-free wrapper around Navigator 1.0.
///
/// Usage: context.nav.push(const DetailsPage(), transition: NavTransition.fade);
class AppNav {
  AppNav._(this._context);

  final BuildContext _context;

  /// Optional app-wide defaults. Set these once at app startup.
  static NavTransition defaultTransition = NavTransition.platform;
  static Duration defaultDuration = const Duration(milliseconds: 320);
  static Duration defaultReverseDuration = const Duration(milliseconds: 260);

  static AppNav of(BuildContext context) => AppNav._(context);

  NavigatorState _navigator({bool rootNavigator = false}) =>
      Navigator.of(_context, rootNavigator: rootNavigator);

  /// Push a new screen and optionally await a result from it.
  Future<T?> push<T extends Object?>(
    Widget page, {
    NavTransition? transition,
    Duration? duration,
    Duration? reverseDuration,
    String? name,
    Object? arguments,
    bool rootNavigator = false,
    bool fullscreenDialog = false,
    RouteTransitionsBuilder? customTransition,
  }) {
    return _navigator(rootNavigator: rootNavigator).push<T>(
      _route<T>(
        page,
        transition: transition ?? defaultTransition,
        duration: duration,
        reverseDuration: reverseDuration,
        name: name,
        arguments: arguments,
        fullscreenDialog: fullscreenDialog,
        customTransition: customTransition,
      ),
    );
  }

  /// Replace the current screen; [result] completes the old route's Future.
  Future<T?> replace<T extends Object?, TO extends Object?>(
    Widget page, {
    TO? result,
    NavTransition? transition,
    Duration? duration,
    Duration? reverseDuration,
    String? name,
    Object? arguments,
    bool rootNavigator = false,
    bool fullscreenDialog = false,
    RouteTransitionsBuilder? customTransition,
  }) {
    return _navigator(rootNavigator: rootNavigator).pushReplacement<T, TO>(
      _route<T>(
        page,
        transition: transition ?? defaultTransition,
        duration: duration,
        reverseDuration: reverseDuration,
        name: name,
        arguments: arguments,
        fullscreenDialog: fullscreenDialog,
        customTransition: customTransition,
      ),
      result: result,
    );
  }

  /// Push a screen and remove every route below it (e.g. after sign-in).
  Future<T?> reset<T extends Object?>(
    Widget page, {
    NavTransition? transition,
    Duration? duration,
    Duration? reverseDuration,
    String? name,
    Object? arguments,
    bool rootNavigator = false,
    bool fullscreenDialog = false,
    RouteTransitionsBuilder? customTransition,
  }) {
    return _navigator(rootNavigator: rootNavigator).pushAndRemoveUntil<T>(
      _route<T>(
        page,
        transition: transition ?? defaultTransition,
        duration: duration,
        reverseDuration: reverseDuration,
        name: name,
        arguments: arguments,
        fullscreenDialog: fullscreenDialog,
        customTransition: customTransition,
      ),
      (route) => false,
    );
  }

  /// Return a typed result to the screen that pushed this one.
  void pop<T extends Object?>([T? result]) => _navigator().pop<T>(result);

  /// Honor PopScope / back interception before attempting a pop.
  Future<bool> maybePop<T extends Object?>([T? result]) =>
      _navigator().maybePop<T>(result);

  bool get canPop => _navigator().canPop();

  /// Pop back to a previously pushed screen with a matching [name].
  /// Register names with push(..., name: '/home').
  void popUntil(String name) =>
      _navigator().popUntil(ModalRoute.withName(name));

  /// Navigate using MaterialApp's onGenerateRoute / routes.
  Future<T?> pushNamed<T extends Object?>(String name, {Object? arguments}) =>
      _navigator().pushNamed<T>(name, arguments: arguments);

  /// Material dialog; its builder has the dialog route's own context.
  Future<T?> dialog<T>(
    WidgetBuilder builder, {
    bool barrierDismissible = true,
    bool useRootNavigator = true,
  }) => showDialog<T>(
    context: _context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
  );

  /// Scrollable, keyboard-friendly modal sheet with an optional drag handle.
  Future<T?> sheet<T>(
    WidgetBuilder builder, {
    bool isScrollControlled = true,
    bool showDragHandle = true,
    bool useSafeArea = true,
    bool useRootNavigator = false,
    bool isDismissible = true,
  }) => showModalBottomSheet<T>(
    context: _context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
  );

  static Route<T> _route<T extends Object?>(
    Widget page, {
    required NavTransition transition,
    Duration? duration,
    Duration? reverseDuration,
    String? name,
    Object? arguments,
    bool fullscreenDialog = false,
    RouteTransitionsBuilder? customTransition,
  }) {
    final settings = (name == null && arguments == null)
        ? null
        : RouteSettings(name: name, arguments: arguments);

    // Preserve Cupertino edge-swipe and platform-appropriate back animations.
    // Duration overrides apply only to custom transitions.
    if (transition == NavTransition.platform && customTransition == null) {
      return MaterialPageRoute<T>(
        builder: (_) => page,
        settings: settings,
        fullscreenDialog: fullscreenDialog,
      );
    }

    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration:
          transition == NavTransition.none && customTransition == null
          ? Duration.zero
          : (duration ?? defaultDuration),
      reverseTransitionDuration:
          transition == NavTransition.none && customTransition == null
          ? Duration.zero
          : (reverseDuration ?? defaultReverseDuration),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        return customTransition?.call(
              context,
              animation,
              secondaryAnimation,
              child,
            ) ??
            _animate(transition, animation, child);
      },
    );
  }

  static Widget _animate(
    NavTransition transition,
    Animation<double> animation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    Widget slide(Offset from) => SlideTransition(
      position: Tween<Offset>(begin: from, end: Offset.zero).animate(curved),
      child: child,
    );

    Widget scale(double from) => ScaleTransition(
      scale: Tween<double>(begin: from, end: 1).animate(curved),
      child: child,
    );

    switch (transition) {
      case NavTransition.platform:
      case NavTransition.none:
        return child;
      case NavTransition.fade:
        return FadeTransition(opacity: curved, child: child);
      case NavTransition.fromRight:
        return slide(const Offset(1, 0));
      case NavTransition.fromLeft:
        return slide(const Offset(-1, 0));
      case NavTransition.fromBottom:
        return slide(const Offset(0, 1));
      case NavTransition.scale:
        return scale(0.92);
      case NavTransition.fadeScale:
        return FadeTransition(opacity: curved, child: scale(0.94));
      case NavTransition.fadeSlideUp:
        return FadeTransition(
          opacity: curved,
          child: slide(const Offset(0, 0.10)),
        );
    }
  }
}

/// Makes navigation available as `context.nav` anywhere in the widget tree.
extension AppNavContext on BuildContext {
  AppNav get nav => AppNav.of(this);
}
