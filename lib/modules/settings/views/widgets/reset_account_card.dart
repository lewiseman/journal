import 'package:journal/common.dart';

class ResetAccountCard extends ConsumerStatefulWidget {
  const ResetAccountCard({super.key});

  @override
  ConsumerState<ResetAccountCard> createState() => _ResetAccountCardState();
}

class _ResetAccountCardState extends ConsumerState<ResetAccountCard> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(syncAccountProvider);
    final backend = ref.watch(syncBackendProvider);
    final reset = ref.watch(accountResetProvider);
    final syncing = ref.watch(
      syncEngineProvider.select((state) => state.isSyncing),
    );
    final danger = context.colors.error;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Reset account data',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: danger,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Permanently delete all notes, diary entries, thoughts, trash and Journal backups from this device and ${backend.displayName}.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Your original photos, imported files and appearance settings are kept. You will be signed out.',
            ),
            if (reset.completed && account == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Account data deleted. Connect an account to start again.',
              ),
            ],
            if (reset.error != null) ...[
              const SizedBox(height: 12),
              Text(reset.error!, style: TextStyle(color: danger)),
            ],
            if (account == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Connect your original sync account before resetting its data.',
              ),
            ],
            if (syncing) ...[
              const SizedBox(height: 12),
              const Text(
                'Wait for sync to finish before resetting account data.',
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('reset-account-data'),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Reset account data'),
              style: OutlinedButton.styleFrom(foregroundColor: danger),
              onPressed:
                  account == null ||
                      reset.blocksDataAccess ||
                      syncing ||
                      _confirming
                  ? null
                  : () async {
                      setState(() => _confirming = true);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => ResetAccountDialog(
                          email: account.email,
                          backendName: backend.displayName,
                        ),
                      );
                      if (!mounted) return;
                      setState(() => _confirming = false);
                      if (confirmed == true) {
                        await ref
                            .read(accountResetProvider.notifier)
                            .reset(expectedAccountId: account.id);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class ResetAccountDialog extends ConsumerStatefulWidget {
  const ResetAccountDialog({
    super.key,
    required this.email,
    required this.backendName,
  });
  final String email;
  final String backendName;

  @override
  ConsumerState<ResetAccountDialog> createState() => _ResetAccountDialogState();
}

class _ResetAccountDialogState extends ConsumerState<ResetAccountDialog> {
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncing = ref.watch(
      syncEngineProvider.select((state) => state.isSyncing),
    );
    return AlertDialog(
      scrollable: true,
      title: const Text('Permanently reset account data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently deletes your journal on this device and all Journal backups in ${widget.email} on ${widget.backendName}. There is no undo.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Close Journal on your other devices. Their local copies are not erased and could upload again unless you clear them before reconnecting.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Photos copied into Journal and cached images are deleted. Original photos, imported files and appearance settings are kept.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('reset-confirmation-input'),
            controller: _confirmation,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Type DELETE to confirm',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (syncing) ...[
            const SizedBox(height: 12),
            const Text(
              'Wait for sync to finish before resetting account data.',
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-reset-account'),
          style: FilledButton.styleFrom(backgroundColor: context.colors.error),
          onPressed: !syncing && _confirmation.text.trim() == 'DELETE'
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('Delete permanently'),
        ),
      ],
    );
  }
}

class ResetAccountProgressScreen extends ConsumerWidget {
  const ResetAccountProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reset = ref.watch(accountResetProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reset account data'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reset.running || reset.checking) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    reset.checking ? 'Checking account reset…' : reset.activity,
                  ),
                ] else ...[
                  const Icon(Icons.error_outline_rounded, size: 40),
                  const SizedBox(height: 16),
                  const Text(
                    'The reset has not finished. Some data may already be permanently deleted. Sync is paused until you finish the reset.',
                  ),
                  if (reset.error != null) ...[
                    const SizedBox(height: 12),
                    Text(reset.error!),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const ValueKey('resume-account-reset'),
                    onPressed: () =>
                        ref.read(accountResetProvider.notifier).reset(),
                    child: const Text('Retry and finish reset'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
