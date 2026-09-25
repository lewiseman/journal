import 'package:journal/common.dart';

void main() {
  runApp(const Journal());
}

class Journal extends StatelessWidget {
  const Journal({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Journal',
      home: RootLayout(),
    );
  }
}
