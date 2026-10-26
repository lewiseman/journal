import 'package:journal/common.dart';
import 'package:journal/modules/settings/views/pages/appearance_page.dart';
import 'package:journal/modules/settings/views/widgets/primary_device_settings.dart';
import 'package:journal/modules/settings/views/widgets/reset_account_card.dart';

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
          const ResetAccountCard(),
        ],
      ),
    );
  }
}
