import 'package:journal/common.dart';

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
