import 'package:journal/common.dart';
import 'package:sync_wise/sync_wise.dart';

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
    final themeMode = ref.watch(
      settingsController.select((settings) => settings.themeMode),
    );
    final themes = ref.watch(appThemesProvider);
    final firstTimeUser = CacheStorage.instance.get(userNameKey) ?? '';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      title: 'Journal',
      home: firstTimeUser.isEmpty ? OnboardingPage() : RootLayout(),
      themeMode: themeMode,
    );
  }
}
