import 'package:journal/common.dart';
import 'package:journal/modules/account/views/pages/reset_account_page.dart';
import 'package:sync_wise/sync_wise.dart';

class SyncAccountSheet extends ConsumerStatefulWidget {
  const SyncAccountSheet({super.key});

  @override
  ConsumerState<SyncAccountSheet> createState() => _SyncAccountSheetState();
}

class _SyncAccountSheetState extends ConsumerState<SyncAccountSheet> {
  bool _working = false;
  bool _confirming = false;
  bool _loggingOut = false;

  Future<void> _sync() async {
    if (_working || ref.read(syncEngineProvider).isSyncing) return;
    setState(() => _working = true);
    try {
      await ref.read(syncEngineProvider.notifier).syncNow(manual: true);
      if (!mounted) return;
      final error = ref.read(syncEngineProvider).lastError;
      if (error != null) _message(error);
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _logout() async {
    if (_working || ref.read(syncEngineProvider).isSyncing) return;
    setState(() {
      _working = true;
      _loggingOut = true;
    });
    try {
      await ref.read(syncAuthProvider).signOut();
      if (!mounted) return;
      ref.invalidate(authStateProvider);
      ref.invalidate(syncEngineProvider);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _loggingOut = false;
        });
      }
    }
  }

  Future<void> _reclaim() async {
    if (_working || _confirming || ref.read(syncEngineProvider).isSyncing) {
      return;
    }
    final expected = ref.read(syncEngineProvider).primary;
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Reclaim primary role?'),
        content: const Text(
          'This device will become primary and restore your synced journal. '
          'The previous primary will become add-only the next time it syncs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-reclaim-primary'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reclaim'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await ref
          .read(syncEngineProvider.notifier)
          .reclaimPrimary(expectedPrimary: expected);
      if (!mounted) return;
      final result = ref.read(syncEngineProvider);
      if (result.role == SyncDeviceRole.primary) {
        _message(
          result.status == EngineSyncState.idle
              ? 'This device is now primary. Your synced journal is restored.'
              : 'This device is now primary. Use Sync now to finish restoring your journal.',
        );
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncEngineProvider);
    final account = ref.watch(syncAccountProvider);
    final backend = ref.watch(syncBackendProvider);
    final primary = sync.role == SyncDeviceRole.primary;
    final busy = _working || sync.isSyncing || account == null;
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sync & devices',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(account?.email ?? 'You are logged out.'),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  sync.status.icon,
                  color: sync.lastError == null ? colors.primary : colors.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sync.statusLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sync.descriptionFor(backend),
                        style: TextStyle(
                          color: sync.lastError == null
                              ? colors.onSurfaceVariant
                              : colors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_working || sync.isSyncing) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                sync.activity ??
                    (_loggingOut ? 'Logging out…' : 'Please wait…'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('account-sync-now'),
              onPressed: busy ? null : _sync,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(),
            ),
            Text(
              primary
                  ? 'This device is primary'
                  : sync.primary == null
                  ? 'Primary device has not been checked yet'
                  : 'Primary device: ${sync.primary!.deviceName}',
              key: const ValueKey('primary-device-status'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              primary
                  ? 'You can edit your existing notes and diary entries here.'
                  : 'Reinstalled the app or replaced your device? Reclaim the primary role to restore your journal and edit existing entries.',
            ),
            if (!primary) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('reclaim-primary-role'),
                onPressed: busy ? null : _reclaim,
                icon: const Icon(Icons.phonelink_setup_rounded),
                label: const Text('Reclaim primary role'),
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(),
            ),
            ListTile(
              key: const ValueKey('account-log-out'),
              contentPadding: EdgeInsets.zero,
              enabled: !busy,
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Log out'),
              subtitle: const Text('Your journal stays on this device.'),
              onTap: busy ? null : _logout,
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const ValueKey('reset-account-data'),
              contentPadding: EdgeInsets.zero,
              enabled: !busy,
              leading: Icon(
                Icons.delete_forever_outlined,
                color: busy ? null : colors.error,
              ),
              title: Text(
                'Reset account data',
                style: TextStyle(color: busy ? null : colors.error),
              ),
              subtitle: Text(
                sync.isSyncing
                    ? 'Wait for sync to finish before resetting account data.'
                    : 'Permanently delete your journal and backups.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: busy
                  ? null
                  : () => context.nav.replace<void, void>(
                      ResetAccountPage(account: account),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
