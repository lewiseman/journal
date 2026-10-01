import 'dart:ui' as ui;

import 'package:journal/common.dart';

final _items = [
  (name: 'Diary', icon: 'diary.png', page: DiaryPage(), color: Colors.brown),
  (
    name: 'Notes',
    icon: 'notes.png',
    page: NotesPage(),
    color: Colors.deepPurple,
  ),
  (name: 'Life', icon: 'leafs.png', page: LifePage(), color: Colors.green),
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
    // final topPadding = MediaQuery.paddingOf(context).top;
    // print(topPadding);
    return Scaffold(
      body: _items.elementAt(_page).page,
      floatingActionButton: switch (_page) {
        1 => GestureDetector(
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => EditNotesPage())),
          child: Image.asset('assets/images/icons/plus_purple.png', height: 50),
        ),
        _ => null,
      },
      floatingActionButtonLocation: switch (_page) {
        0 => FloatingActionButtonLocation.endFloat,
        _ => FloatingActionButtonLocation.endFloat,
      },
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _page,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedItemColor: _items.elementAt(_page).color,
        unselectedItemColor: Colors.black,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
        onTap: (value) {
          setState(() {
            _page = value;
          });
        },
        items: [
          for (final x in _items)
            BottomNavigationBarItem(
              label: x.name,
              icon: Image.asset('assets/images/icons/${x.icon}', height: 30),
              activeIcon: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Transform.translate(
                    offset: const Offset(0, 2),
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 2.5,
                        sigmaY: 2.5,
                      ),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          Colors.black.withValues(alpha: 0.24),
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          'assets/images/icons/${x.icon}',
                          height: 44,
                        ),
                      ),
                    ),
                  ),
                  Image.asset('assets/images/icons/${x.icon}', height: 44),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
