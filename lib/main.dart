import 'package:journal/common.dart';

void main() {
  runApp(const Journal());
}

class Journal extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Journal', home: RootLayout());
  }
}
