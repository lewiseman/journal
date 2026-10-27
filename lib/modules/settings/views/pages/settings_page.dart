import 'package:journal/common.dart';
import 'package:journal/modules/settings/views/pages/appearance_page.dart';
import 'package:journal/modules/settings/views/widgets/primary_device_settings.dart';
import 'package:journal/modules/settings/views/widgets/reset_account_card.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';

class SettingsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: Text('Appearance'),
            onTap: () {
              context.nav.push(AppearancePage());
            },
          ),
          const PrimaryDeviceSettings(),
          const CompanionSettingsTile(),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('AI task history'),
            subtitle: const Text('Recover summaries and review recent results'),
            onTap: () => context.nav.push(const SummaryHistoryPage()),
          ),
          const ResetAccountCard(),
        ],
      ),
    );
  }
}
