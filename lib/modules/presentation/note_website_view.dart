import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'website_contract.dart';

/// Shows a note's generated website: re-sanitized, with JavaScript off and
/// every navigation blocked, so the page can only draw itself.
class NoteWebsiteView extends StatefulWidget {
  const NoteWebsiteView({super.key, required this.html});
  final String html;

  @override
  State<NoteWebsiteView> createState() => _NoteWebsiteViewState();
}

class _NoteWebsiteViewState extends State<NoteWebsiteView> {
  WebViewController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NoteWebsiteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) _load();
  }

  Future<void> _load() async {
    final html = widget.html;
    // Without a platform web view (tests, unsupported desktops) nothing loads.
    if (WebViewPlatform.instance == null) return;
    String safe;
    try {
      // Synced pages are checked again: another device may be older or wrong.
      safe = await sanitizeWebsiteBounded(html);
    } catch (_) {
      if (mounted && html == widget.html) setState(() => _failed = true);
      return;
    }
    if (!mounted || html != widget.html) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              request.url.startsWith('about:blank') ||
                  request.url.startsWith('about:srcdoc')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    await controller.loadHtmlString(safe);
    if (mounted && html == widget.html) {
      setState(() {
        _controller = controller;
        _failed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Semantics(
      key: const ValueKey('note-website-view'),
      label: 'Note website',
      child: _failed
          ? const Center(child: Text('This website could not be shown safely.'))
          : controller == null
          ? const SizedBox.expand()
          : WebViewWidget(
              controller: controller,
              // The page scrolls itself inside the note's scrolling paper.
              gestureRecognizers: {
                Factory<VerticalDragGestureRecognizer>(
                  VerticalDragGestureRecognizer.new,
                ),
              },
            ),
    );
  }
}
