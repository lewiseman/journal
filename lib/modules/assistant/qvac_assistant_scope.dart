import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final qvacAssistantProvider = Provider<QvacAssistantController>((ref) {
  final controller = QvacAssistantController();
  ref.onDispose(controller.dispose);
  return controller;
});

typedef QvacAssistantSheetBuilder = Widget Function(
  BuildContext context,
  ScrollController scrollController,
);

/// Session-only presentation state. Connection and retry work stays in the
/// existing companion controller; moving the assistant never starts a probe.
class QvacAssistantController extends ChangeNotifier {
  final dockLink = LayerLink();
  final _routes = <Route<dynamic>>[];
  final _pages = <Route<dynamic>, _Destination>{};
  final _contents = <Route<dynamic>, Map<String, QvacAssistantSheetBuilder>>{};
  Rect? dockRect;
  bool dismissed = false;
  bool _scheduled = false;
  bool _disposed = false;

  Route<dynamic>? get _page =>
      _routes.whereType<PageRoute<dynamic>>().lastOrNull;
  _Destination? get _destination => _pages[_page];
  _Destination? get _nearestDestination => _routes.reversed
      .map((route) => _pages[route])
      .whereType<_Destination>()
      .firstOrNull;
  bool get visible =>
      !dismissed &&
      _routes.lastOrNull is PageRoute &&
      (_nearestDestination?.enabled ?? false);
  bool get docking => visible && (_destination?.dock ?? false);
  bool get atRoot => _destination?.root ?? false;
  String get pageLabel => _destination?.label ?? 'this page';
  QvacAssistantSheetBuilder? get sheetBuilder => _contents[_page]?[pageLabel];

  void dismiss() {
    dismissed = true;
    _changed();
  }

  void _changed() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    // Route notifications and anchor measurements can arrive during layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _register(Route<dynamic> route, _Destination destination) {
    if (_pages[route] == destination) return;
    _pages[route] = destination;
    _changed();
  }

  void _unregister(Route<dynamic>? route) {
    if (_pages.remove(route) != null) _changed();
  }

  void _registerContent(
    Route<dynamic> route,
    String label,
    QvacAssistantSheetBuilder builder,
  ) {
    (_contents[route] ??= {})[label] = builder;
  }

  void _unregisterContent(Route<dynamic>? route, String label) {
    final contents = _contents[route];
    contents?.remove(label);
    if (contents?.isEmpty ?? false) _contents.remove(route);
  }

  void _measureDock(Rect? rect) {
    if (dismissed || dockRect == rect) return;
    dockRect = rect;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class QvacAssistantObserver extends NavigatorObserver {
  QvacAssistantObserver(this.controller);
  final QvacAssistantController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) controller._routes.clear();
    controller._routes.add(route);
    controller._changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    didRemove(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller._routes.remove(route);
    controller._unregister(route);
    controller._changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : controller._routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        controller._routes.removeAt(index);
      } else {
        controller._routes[index] = newRoute;
      }
    }
    controller._unregister(oldRoute);
    controller._changed();
  }
}

class _Destination {
  const _Destination(this.label, this.enabled, this.dock, this.root);
  final String label;
  final bool enabled, dock, root;

  @override
  bool operator ==(Object other) =>
      other is _Destination &&
      label == other.label &&
      enabled == other.enabled &&
      dock == other.dock &&
      root == other.root;
  @override
  int get hashCode => Object.hash(label, enabled, dock, root);
}

class QvacAssistantScope extends InheritedWidget {
  const QvacAssistantScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final QvacAssistantController controller;
  static QvacAssistantController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<QvacAssistantScope>()
      ?.controller;
  @override
  bool updateShouldNotify(QvacAssistantScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Supplies tools for one page without changing the root tab's visibility or
/// docking rules. Retained tabs only supply content when their label is active.
class QvacAssistantContent extends StatefulWidget {
  const QvacAssistantContent({
    super.key,
    required this.label,
    required this.builder,
    required this.child,
  });
  final String label;
  final QvacAssistantSheetBuilder builder;
  final Widget child;

  @override
  State<QvacAssistantContent> createState() => _QvacAssistantContentState();
}

class _QvacAssistantContentState extends State<QvacAssistantContent> {
  QvacAssistantController? _controller;
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unregister();
    _controller = QvacAssistantScope.maybeOf(context);
    _route = ModalRoute.of(context);
    _register();
  }

  void _register() {
    final route = _route;
    if (route != null) {
      _controller?._registerContent(route, widget.label, widget.builder);
    }
  }

  void _unregister() => _controller?._unregisterContent(_route, widget.label);

  @override
  void didUpdateWidget(QvacAssistantContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller?._unregisterContent(_route, oldWidget.label);
    _register();
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Marks a destination independently of how it was pushed (including direct
/// MaterialPageRoutes). Without a host this is just a transparent wrapper.
class QvacAssistantPage extends StatefulWidget {
  const QvacAssistantPage({
    super.key,
    required this.child,
    this.label = 'this page',
    this.enabled = true,
    this.dock = false,
    this.root = false,
  });
  final Widget child;
  final String label;
  final bool enabled, dock, root;
  @override
  State<QvacAssistantPage> createState() => _QvacAssistantPageState();
}

class _QvacAssistantPageState extends State<QvacAssistantPage> {
  QvacAssistantController? _controller;
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = QvacAssistantScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (controller != _controller || route != _route) {
      _controller?._unregister(_route);
      _controller = controller;
      _route = route;
    }
    _register();
  }

  void _register() {
    final route = _route;
    if (route != null) {
      _controller?._register(
        route,
        _Destination(widget.label, widget.enabled, widget.dock, widget.root),
      );
    }
  }

  @override
  void didUpdateWidget(QvacAssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  @override
  void dispose() {
    _controller?._unregister(_route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Keeps More's original layout while the single overlay image occupies its
/// illustration slot. The layer link follows scrolling without a ticker;
/// measurements decide when the slot has left the visible viewport.
class QvacAssistantDock extends StatefulWidget {
  const QvacAssistantDock({super.key, required this.child});
  final Widget child;
  @override
  State<QvacAssistantDock> createState() => _QvacAssistantDockState();
}

class _QvacAssistantDockState extends State<QvacAssistantDock> {
  final _anchor = GlobalKey();
  ScrollPosition? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_scrolled);
      _scroll = scroll;
      _scroll?.addListener(_scrolled);
    }
  }

  void _scrolled() {
    // Scrolling often moves a retained layer without repainting its children.
    (_anchor.currentContext?.findRenderObject() as _RenderDock?)
        ?.measureAfterFrame();
  }

  @override
  void dispose() {
    _scroll?.removeListener(_scrolled);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = QvacAssistantScope.maybeOf(context);
    if (controller == null) return widget.child;
    return ListenableBuilder(
      listenable: controller,
      child: widget.child,
      builder: (context, child) => _DockAnchor(
        key: _anchor,
        onRect: controller._measureDock,
        child: CompositedTransformTarget(
          link: controller.dockLink,
          child: Opacity(opacity: controller.dismissed ? 1 : 0, child: child),
        ),
      ),
    );
  }
}

class _DockAnchor extends SingleChildRenderObjectWidget {
  const _DockAnchor({super.key, required this.onRect, required super.child});
  final ValueChanged<Rect?> onRect;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDock(onRect);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderDock renderObject,
  ) {
    renderObject.onRect = onRect;
  }
}

class _RenderDock extends RenderProxyBox {
  _RenderDock(this.onRect);
  ValueChanged<Rect?> onRect;
  bool _measurementScheduled = false;

  void measureAfterFrame() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (attached && hasSize) _measure();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _measure() {
    final rect = localToGlobal(Offset.zero) & size;
    final viewport = RenderAbstractViewport.maybeOf(this) as RenderObject?;
    var bounds = viewport is RenderBox
        ? viewport.localToGlobal(Offset.zero) & viewport.size
        : rect;
    if (viewport is RenderViewport) {
      var obstruction = 0.0;
      for (
        var sliver = viewport.firstChild;
        sliver != null;
        sliver = viewport.childAfter(sliver)
      ) {
        obstruction += sliver.geometry?.maxScrollObstructionExtent ?? 0;
      }
      // More's pinned account header paints above the scroll content.
      bounds = Rect.fromLTRB(
        bounds.left,
        bounds.top + obstruction,
        bounds.right,
        bounds.bottom,
      );
    }
    onRect(
      bounds.contains(rect.topLeft) && bounds.contains(rect.bottomRight)
          ? rect
          : null,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _measure();
    super.paint(context, offset);
  }

  @override
  void detach() {
    onRect(null);
    super.detach();
  }
}
