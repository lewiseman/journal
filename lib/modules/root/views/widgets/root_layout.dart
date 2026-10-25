import 'package:journal/common.dart';
import 'package:journal/modules/root/views/widgets/bottom_navbar.dart';

class RootLayout extends StatefulWidget {
  const new({super.key});

  @override
  State<RootLayout> createState() => _RootLayoutState();
}

class _RootLayoutState extends State<RootLayout>
    with SingleTickerProviderStateMixin {
  int _page = 0;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  final List<Widget> _pages = [
    const DiaryPage(),
    NotesPage(),
    TasksPage(),
    MorePage(),
  ];

  void _select(int index) {
    if (index == _page) return;
    setState(() {
      _page = index;
    });
    _reveal.forward(from: 0);
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: Tween<double>(
          begin: 0.78,
          end: 1,
        ).animate(CurvedAnimation(parent: _reveal, curve: Curves.easeOut)),
        child: IndexedStack(
          index: _page,
          children: [
            for (var index = 0; index < _pages.length; index++)
              TickerMode(enabled: index == _page, child: _pages[index]),
          ],
        ),
      ),
      bottomNavigationBar: JournalBottomNavbar(
        selectedIndex: _page,
        onSelected: _select,
      ),
    );
  }
}
