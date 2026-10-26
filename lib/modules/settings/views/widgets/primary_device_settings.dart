import 'package:journal/common.dart';
import 'package:sync_wise/sync_wise.dart';

class PrimaryDeviceSettings extends ConsumerStatefulWidget {
  const PrimaryDeviceSettings({super.key});

  @override
  ConsumerState<PrimaryDeviceSettings> createState() =>
      _PrimaryDeviceSettingsState();
}

class _PrimaryDeviceSettingsState extends ConsumerState<PrimaryDeviceSettings> {
  bool _working = false;
  bool _confirming = false;

  Future<void> _connect() async {
    setState(() => _working = true);
    try {
      final account = await ref.read(syncAuthProvider).signIn();
      if (account != null && mounted) {
        await ref.read(syncEngineProvider.notifier).syncNow(manual: true);
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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
    final auth = ref.watch(syncAuthProvider);
    final account = ref.watch(authStateProvider).value ?? auth.currentUser;
    final primary = sync.role == SyncDeviceRole.primary;
    final busy = _working || sync.isSyncing;
    final colors = context.colors;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sync & devices',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              account?.email ??
                  'Connect the account containing your synced journal.',
            ),
            if (account != null) ...[
              const SizedBox(height: 16),
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
            ],
            if (busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(sync.activity ?? 'Connecting…'),
            ],
            if (sync.lastError != null) ...[
              const SizedBox(height: 12),
              Text(sync.lastError!, style: TextStyle(color: colors.error)),
            ] else if (sync.status == EngineSyncState.offline) ...[
              const SizedBox(height: 12),
              const Text('Connect to the internet and try again.'),
            ],
            const SizedBox(height: 16),
            if (account == null)
              FilledButton.icon(
                key: const ValueKey('settings-connect-account'),
                onPressed: busy ? null : _connect,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Connect account'),
              )
            else if (!primary)
              FilledButton.icon(
                key: const ValueKey('reclaim-primary-role'),
                onPressed: busy ? null : _reclaim,
                icon: const Icon(Icons.phonelink_setup_rounded),
                label: const Text('Reclaim primary role'),
              )
            else
              FilledButton.icon(
                key: const ValueKey('settings-sync-now'),
                onPressed: busy
                    ? null
                    : () => ref
                          .read(syncEngineProvider.notifier)
                          .syncNow(manual: true),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sync now'),
              ),
          ],
        ),
      ),
    );
  }
}
