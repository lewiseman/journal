import 'package:journal/common.dart';
import 'package:sync_wise/sync_wise.dart';

class ResetAccountPage extends ConsumerStatefulWidget {
  const ResetAccountPage({super.key, required this.account});

  final SyncAccount account;

  @override
  ConsumerState<ResetAccountPage> createState() => _ResetAccountPageState();
}

class _ResetAccountPageState extends ConsumerState<ResetAccountPage> {
  final _confirmation = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_submitting ||
        _confirmation.text.trim() != 'DELETE' ||
        ref.read(syncAccountProvider)?.id != widget.account.id ||
        ref.read(syncEngineProvider).isSyncing ||
        ref.read(accountResetProvider).blocksDataAccess) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(accountResetProvider.notifier)
          .reset(expectedAccountId: widget.account.id);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(syncAccountProvider);
    final backend = ref.watch(syncBackendProvider);
    final reset = ref.watch(accountResetProvider);
    final syncing = ref.watch(
      syncEngineProvider.select((state) => state.isSyncing),
    );
    final sameAccount = account?.id == widget.account.id;
    final busy = _submitting || reset.blocksDataAccess;
    final canReset =
        sameAccount &&
        !busy &&
        !syncing &&
        _confirmation.text.trim() == 'DELETE';
    final danger = context.colors.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset account data')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Permanently reset account data?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: danger,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This permanently deletes all notes, diary entries, thoughts, trash and Journal backups on this device and in ${widget.account.email} on ${backend.displayName}. There is no undo.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Close Journal on your other devices. Their local copies are not erased and could upload again unless you clear them before reconnecting.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Photos copied into Journal and cached images are deleted. Your original photos, imported files and appearance settings are kept. You will be signed out.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Summary recovery data is cleared on this phone. Accepted AI work on your computer may remain encrypted for up to 24 hours; revoke this phone there to remove it immediately.',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const ValueKey('reset-confirmation-input'),
                    controller: _confirmation,
                    enabled: !busy && sameAccount,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Type DELETE to confirm',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (!sameAccount) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Reconnect ${widget.account.email} before resetting its data.',
                    ),
                  ],
                  if (syncing) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Wait for sync to finish before resetting account data.',
                    ),
                  ],
                  if (reset.error != null) ...[
                    const SizedBox(height: 16),
                    Text(reset.error!, style: TextStyle(color: danger)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('confirm-reset-account'),
                    style: FilledButton.styleFrom(
                      backgroundColor: danger,
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onPressed: canReset ? _reset : null,
                    child: const Text('Delete permanently'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
