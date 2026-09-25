import 'package:journal/common.dart';

final _items = [
  (
    name: 'Diary',
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book,
    page: DiaryPage(),
  ),
  (
    name: 'Notes',
    icon: Icons.note_alt_outlined,
    activeIcon: Icons.note_alt,
    page: NotesPage(),
  ),
  (
    name: 'Life',
    icon: Icons.spa_outlined,
    activeIcon: Icons.spa,
    page: LifePage(),
  ),
  (
    name: 'Account',
    icon: Icons.person_outline,
    activeIcon: Icons.person,
    page: AccountPage(),
  ),
];

class RootLayout extends StatefulWidget {
  const RootLayout({super.key});

  @override
  State<RootLayout> createState() => _RootLayoutState();
}

class _RootLayoutState extends State<RootLayout> {
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _items.elementAt(_page).page,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _page,
        selectedLabelStyle: TextStyle(color: Colors.black),
        unselectedLabelStyle: TextStyle(color: Colors.blueGrey),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.blueGrey,
        onTap: (value) {
          setState(() {
            _page = value;
          });
        },
        items: [
          for (final x in _items)
            BottomNavigationBarItem(
              label: x.name,
              icon: Icon(x.icon, color: Colors.blueGrey),
              activeIcon: Icon(x.activeIcon, color: Colors.black),
            ),
        ],
      ),
    );
  }
}
