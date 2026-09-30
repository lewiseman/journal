import 'package:journal/common.dart';

final _items = [
  (name: 'Diary', icon: 'diary.png', page: DiaryPage()),
  (name: 'Notes', icon: 'notes.png', page: NotesPage()),
  (name: 'Life', icon: 'leafs.png', page: LifePage()),
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
      floatingActionButton: switch (_page) {
        0 => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.large(
              tooltip: 'Add',
              elevation: 0,
              backgroundColor: Colors.transparent,
              onPressed: () {},
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Image.asset('assets/images/icons/pencil.png'),
              ),
            ),
          ],
        ),
        _ => null,
      },
      floatingActionButtonLocation: switch (_page) {
        0 => FloatingActionButtonLocation.centerFloat,
        _ => FloatingActionButtonLocation.endFloat,
      },
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _page,
        
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black,
        onTap: (value) {
          setState(() {
            _page = value;
          });
        },
        items: [
          for (final x in _items)
            BottomNavigationBarItem(
              label: x.name,
              
              icon: ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.grey, BlendMode.srcOut),
                child: Image.asset('assets/images/icons/${x.icon}', height: 40),
              ),
              activeIcon: Image.asset(
                'assets/images/icons/${x.icon}',
                height: 40,
              ),
            ),
        ],
      ),
    );
  }
}
