import 'dart:async';

import 'package:journal/common.dart';
import 'package:journal/modules/flow/views/widgets/flow_thought_card.dart';
import 'package:journal/modules/recall/hybrid_retriever.dart';
import 'package:journal/modules/recall/recall_contract.dart';

/// S03b: finds earlier Flow thoughts by keyword and, when this phone has
/// opted in, by meaning. Choosing one pops with it.
class ThoughtRecallPage extends ConsumerStatefulWidget {
  const ThoughtRecallPage({super.key});

  @override
  ConsumerState<ThoughtRecallPage> createState() => _ThoughtRecallPageState();
}

class _ThoughtRecallPageState extends ConsumerState<ThoughtRecallPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<ThoughtEntity> _results = const [];
  String? _note;
  bool _searching = false;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _request++;
      setState(() {
        _results = const [];
        _note = null;
        _searching = false;
      });
      return;
    }
    // Keyword matches show at once; meaning refines them after a pause.
    final thoughts = ref.read(thoughtsStreamProvider).value ?? const [];
    final byUuid = {for (final t in thoughts) t.uuid: t};
    setState(() {
      _searching = true;
      _results = [
        for (final h in HybridRetriever.keywordHits(
          query,
          sources: RecallSource.thoughts(thoughts),
          kinds: const {RecallKind.thought},
        ))
          ?byUuid[h.source.id],
      ];
    });
    final request = ++_request;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final result = await ref
          .read(hybridRetrieverProvider)
          .search(
            query,
            sources: RecallSource.thoughts(thoughts),
            kinds: const {RecallKind.thought},
          );
      if (!mounted || request != _request) return;
      setState(() {
        _searching = false;
        _note = result.fallback;
        _results = [for (final h in result.hits) ?byUuid[h.source.id]];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final caption = TextStyle(
      fontSize: 12,
      color: context.colors.onSurfaceVariant,
    );
    final query = _query.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Recall a thought')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            key: const ValueKey('thought-recall-field'),
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            decoration: const InputDecoration(
              hintText: 'What was that thought about…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          if (_searching)
            Text('Searching by keywords and meaning…', style: caption)
          else if (_note != null && query.isNotEmpty)
            Text(
              _note!,
              key: const ValueKey('thought-recall-note'),
              style: caption,
            ),
          const SizedBox(height: 8),
          if (query.isNotEmpty && !_searching && _results.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('No earlier thought matches yet.'),
            ),
          for (final thought in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 150,
                child: FlowThoughtCard(
                  key: ValueKey('thought-recall-${thought.uuid}'),
                  thought: thought,
                  onTap: () => Navigator.of(context).pop(thought),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
