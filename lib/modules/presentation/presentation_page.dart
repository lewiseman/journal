import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:sync_wise/sync_wise.dart';

import 'presentation_body.dart';
import 'presentation_contract.dart';
import 'presentation_repository.dart';

class PresentationPage extends ConsumerStatefulWidget {
  const PresentationPage({super.key, this.source});
  final PresentationSourceRef? source;
  @override
  ConsumerState<PresentationPage> createState() => _PresentationPageState();
}

class _PresentationPageState extends ConsumerState<PresentationPage> {
  final _intent = TextEditingController();
  String? _compiledText;
  Future<SafePresentationDocument>? _document;
  @override
  void dispose() {
    _intent.dispose();
    super.dispose();
  }

  void _error(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is StateError
            ? error.message.toString()
            : 'Could not change this presentation.',
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final source =
        widget.source ??
        (handle?.isPresentation == true ? handle!.presentationSource : null);
    final repository = ref.watch(presentationRepositoryProvider);
    final record = source == null
        ? null
        : ref.watch(presentationRecordProvider(source.key)).value;
    final current = source == null
        ? null
        : ref.watch(presentationSourceProvider(source)).value ??
              repository.source(source);
    final canEdit =
        ref.watch(syncDeviceRoleProvider) != SyncDeviceRole.secondary;
    PresentationSnapshot? snapshot;
    PresentationBlocks? blocks;
    String? sourceError;
    try {
      if (handle?.isPresentation == true &&
          handle?.presentationSource?.key == source?.key &&
          handle?.localSource != null) {
        snapshot = PresentationSnapshot.decode(handle!.localSource!);
      } else {
        snapshot = current;
      }
      if (snapshot != null) {
        blocks = PresentationBlocks(
          snapshot.content,
          markdown: snapshot.ref.kind == 'note',
        );
      }
    } catch (_) {
      sourceError = 'This source is too large or complex for presentation. The original is available below.';
    }
    final thisTask =
        handle?.isPresentation == true &&
        handle?.presentationSource?.key == source?.key;
    final result = thisTask ? state.text : null;
    if (result != _compiledText) {
      _compiledText = result;
      _document = result == null || blocks == null
          ? null
          : compilePresentationBounded(result, blocks.nodes.length);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Presentation')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Style saved words on this device. Your wording, paragraph order and Markdown structure stay the same. Only this text and your styling request go to your trusted computer.',
          ),
          const Text(
            'Small models may return incompatible styling. Those results are rejected; you can retry explicitly.',
          ),
          const SizedBox(height: 16),
          if (!canEdit)
            const Text(
              'This device can preview; accepting or reverting requires editing permission.',
            ),
          if (sourceError != null) Text(sourceError),
          if (snapshot != null) ...[
            const Text(
              'Original',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(
              snapshot.content,
              key: const ValueKey('presentation-original'),
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: snapshot!.content)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy original'),
            ),
          ] else
            const Text('The saved source is unavailable.'),
          if (handle == null && source != null && blocks != null) ...[
            TextField(
              key: const ValueKey('presentation-intent'),
              controller: _intent,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Styling request (optional)',
                hintText:
                    'For example: comfortable spacing and gentle emphasis',
              ),
            ),
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => controller.startPresentation(
                      source,
                      intent: _intent.text.trim(),
                    ),
              key: const ValueKey('presentation-generate'),
              child: const Text('Generate presentation'),
            ),
          ],
          if (handle != null && !thisTask) ...[
            const Text(
              'Another AI task occupies the recoverable preview. Open AI task history to finish or clear it.',
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SummaryHistoryPage(),
                ),
              ),
              child: const Text('AI task history'),
            ),
          ],
          if (thisTask) ...[
            Text(
              summaryPhaseLabel(state.phase),
              key: const ValueKey('presentation-phase'),
            ),
            if (state.stale)
              const Text(
                'The source changed. Generate a new presentation before accepting.',
              ),
            if (state.message != null) Text(state.message!),
            if (state.busy) const LinearProgressIndicator(),
            if (_document != null && blocks != null && snapshot != null)
              FutureBuilder<SafePresentationDocument>(
                future: _document,
                builder: (context, parsed) {
                  if (parsed.hasError) {
                    return const Text(
                      'The result does not meet the safe presentation rules. Your original is unchanged.',
                    );
                  }
                  if (!parsed.hasData) return const LinearProgressIndicator();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Styled preview',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      SafePresentationBody(
                        key: const ValueKey('presentation-preview'),
                        blocks: blocks!,
                        document: parsed.data!,
                        original: snapshot!.content,
                      ),
                      FilledButton(
                        key: const ValueKey('presentation-accept'),
                        onPressed:
                            canEdit &&
                                !state.stale &&
                                !state.busy &&
                                state.phase == 'completed'
                            ? () async {
                                if (await controller.acceptPresentation() &&
                                    mounted) {
                                  setState(() {});
                                }
                              }
                            : null,
                        child: const Text('Accept presentation'),
                      ),
                    ],
                  );
                },
              ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: state.busy ? null : controller.retry,
                  child: const Text('Retrieve / retry'),
                ),
                if (!state.terminal)
                  TextButton(
                    onPressed: state.busy ? null : controller.cancel,
                    child: const Text('Cancel task'),
                  ),
                if (state.terminal)
                  TextButton(
                    key: const ValueKey('presentation-reject'),
                    onPressed: state.busy ? null : controller.clear,
                    child: const Text('Reject / clear preview'),
                  ),
              ],
            ),
          ] else if (state.message != null && handle == null)
            Text(state.message!),
          if (record != null && source != null) ...[
            const Divider(),
            Text(
              record.enabled ? 'Accepted locally' : 'Original view restored',
            ),
            if (current != null)
              PresentationBody(
                source: source,
                content: current.content,
                fallback: SelectableText(current.content),
              ),
            if (record.enabled)
              TextButton(
                key: const ValueKey('presentation-revert'),
                onPressed: !canEdit
                    ? null
                    : () {
                        try {
                          repository.revert(source);
                        } catch (e) {
                          _error(e);
                        }
                      },
                child: const Text('Revert to original'),
              ),
            Builder(
              builder: (context) {
                try {
                  final saved = PresentationSnapshot.decode(record.snapshot);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!repository.matches(saved))
                        const Text(
                          'This presentation belongs to an earlier source version. The reader uses your current words.',
                        ),
                      ExpansionTile(
                        title: const Text('Recover original snapshot'),
                        children: [
                          SelectableText(saved.content),
                          TextButton(
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: saved.content),
                            ),
                            child: const Text('Copy saved original'),
                          ),
                        ],
                      ),
                    ],
                  );
                } catch (_) {
                  return const Text(
                    'The saved presentation is unreadable. Your current source is preserved.',
                  );
                }
              },
            ),
            TextButton(
              onPressed: !canEdit
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Remove presentation copy?'),
                          content: const Text(
                            'Remove the local styling and its saved source snapshot. Current journal text is kept.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Keep'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        try {
                          repository.remove(source);
                        } catch (e) {
                          _error(e);
                        }
                      }
                    },
              child: const Text('Remove local presentation copy'),
            ),
          ],
        ],
      ),
    );
  }
}
