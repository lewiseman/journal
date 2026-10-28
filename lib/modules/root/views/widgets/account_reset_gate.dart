import 'package:journal/common.dart';
import 'package:journal/modules/account/views/widgets/reset_account_progress.dart';

final journalNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  // A fast reset can complete before a frame paints the blocking screen.
  // A new Navigator still disposes every old route and editor in that case.
  ref.watch(accountResetProvider.select((state) => state.completed));
  return GlobalKey<NavigatorState>();
});

/// Replaces the whole Navigator, including open editors, while reset is pending.
class AccountResetGate extends ConsumerWidget {
  const AccountResetGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reset = ref.watch(accountResetProvider);
    ref.listen(accountResetProvider, (previous, next) {
      if (next.completed && previous?.completed != true) {
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
        ref.invalidate(notesStreamProvider);
        ref.invalidate(trashNotesStreamProvider);
        ref.invalidate(conflictNotesStreamProvider);
        ref.invalidate(diaryDaysProvider);
        ref.invalidate(authStateProvider);
      }
      final message = next.completed && previous?.completed != true
          ? 'Account data reset. You are signed out.'
          : previous?.running == true && !next.blocksDataAccess
          ? next.error
          : null;
      if (message != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(SnackBar(content: Text(message)));
          }
        });
      }
    });
    return reset.blocksDataAccess ? const ResetAccountProgressScreen() : child;
  }
}
