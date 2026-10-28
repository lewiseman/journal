import 'package:journal/common.dart';
import 'package:sync_wise/sync_wise.dart';
import 'package:journal/modules/root/views/widgets/account_reset_gate.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/recall/recall_indexer.dart';
import 'package:journal/modules/assistant/qvac_assistant.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';

final _assistantObserverProvider = Provider<NavigatorObserver>((ref) {
  // Account reset creates a new Navigator; its observer must be new as well.
  ref.watch(journalNavigatorKeyProvider);
  return QvacAssistantObserver(ref.watch(qvacAssistantProvider));
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CacheStorage.init();
  objectbox = await ObjectBox.create();
  await DeviceIdentityService.initialize();
  runApp(ProviderScope(child: const Journal()));
}

class Journal extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(companionControllerProvider.select((_) => null));
    ref.watch(noteSummaryProvider.select((_) => null));
    // Opted in: keeps today's diary question requested while connected.
    if (ref.watch(dailyQuestionEnabledProvider)) {
      ref.watch(dailyQuestionProvider.select((_) => null));
    }
    // Keeps opted-in search-by-meaning vectors current while the app is open.
    ref.watch(recallIndexerProvider.select((_) => null));
    final themeMode = ref.watch(
      settingsController.select((settings) => settings.themeMode),
    );
    final themes = ref.watch(appThemesProvider);
    final assistant = ref.watch(qvacAssistantProvider);
    final navigatorKey = ref.watch(journalNavigatorKeyProvider);
    final firstTimeUser = CacheStorage.instance.get(userNameKey) ?? '';
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [ref.watch(_assistantObserverProvider)],
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      title: 'Journal',
      builder: (context, child) => AccountResetGate(
        child: QvacAssistantHost(
          controller: assistant,
          navigatorKey: navigatorKey,
          child: child!,
        ),
      ),
      home: firstTimeUser.isEmpty ? OnboardingPage() : RootLayout(),
      themeMode: themeMode,
    );
  }
}
