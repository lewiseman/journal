import 'package:journal/common.dart';
import 'package:journal/modules/settings/views/pages/appearance_page.dart';

class SettingsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        children: [
          ListTile(
            title: Text('Appearance'),
            onTap: () {
              context.nav.push(AppearancePage());
            },
          ),
        ],
      ),
    );
  }
}
