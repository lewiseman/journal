import 'package:flutter/material.dart';
import 'package:journal/modules/notes/metadata/note_help_pages.dart';

import 'note_ai_widgets.dart';

/// The collection has its own tools; individual notes keep their editing tools.
class NotesAssistant extends StatefulWidget {
  const NotesAssistant({
    super.key,
    required this.scrollController,
    required this.onUseIdea,
    required this.onSearch,
  });
  final ScrollController scrollController;
  final ValueChanged<String> onUseIdea;

  /// Opens AI note search full screen once the sheet has closed.
  final VoidCallback onSearch;

  @override
  State<NotesAssistant> createState() => _NotesAssistantState();
}

class _NotesAssistantState extends State<NotesAssistant> {
  final _navigator = GlobalKey<NavigatorState>();

  PageRoute<void> _route(WidgetBuilder builder, {bool maintainState = true}) =>
      PageRouteBuilder<void>(
        maintainState: maintainState,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => builder(context),
      );

  void _useIdea(String idea) {
    Navigator.of(context).pop();
    widget.onUseIdea(idea);
  }

  void _openSearch() {
    Navigator.of(context).pop();
    widget.onSearch();
  }

  void _openIdeas() {
    FocusScope.of(context).unfocus();
    if (widget.scrollController.hasClients) widget.scrollController.jumpTo(0);
    _navigator.currentState!.push<void>(
      _route((_) => NoteIdeasPage(onUseIdea: _useIdea)),
    );
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<void>(
    onPopWithResult: (_) => _navigator.currentState!.pop(),
    child: Navigator(
      key: _navigator,
      onGenerateRoute: (_) => _route(
        (_) => _NotesAssistantMenu(
          scrollController: widget.scrollController,
          onIdeas: _openIdeas,
          onSearch: _openSearch,
        ),
        maintainState: false,
      ),
    ),
  );
}

class _NotesAssistantMenu extends StatelessWidget {
  const _NotesAssistantMenu({
    required this.scrollController,
    required this.onIdeas,
    required this.onSearch,
  });
  final ScrollController scrollController;
  final VoidCallback onIdeas, onSearch;

  @override
  Widget build(BuildContext context) {
    final narrow =
        MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final ideas = NoteAiToolCard(
      key: const ValueKey('notes-assistant-ideas'),
      tool: NoteAiTool.ideas,
      horizontal: narrow,
      onTap: onIdeas,
    );
    final search = NoteAiToolCard(
      key: const ValueKey('notes-assistant-search'),
      tool: NoteAiTool.search,
      horizontal: narrow,
      onTap: onSearch,
    );
    return Material(
      color: noteAiPaper(context),
      child: ListView(
        key: const ValueKey('notes-assistant-actions'),
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (narrow) ...[
            ideas,
            const SizedBox(height: 10),
            search,
          ] else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ideas),
                  const SizedBox(width: 10),
                  Expanded(child: search),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
