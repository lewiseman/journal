import 'package:flutter/material.dart';

final _items = [
  (name: 'Diary', icon: '', activeIcon: '', page: Text('data')),
  (name: 'Notes', icon: '', activeIcon: '', page: Text('data')),
  (name: 'Life', icon: '', activeIcon: '', page: Text('data')),
  (name: 'Account', icon: '', activeIcon: '', page: Text('data')),
];

class RootLayout extends StatelessWidget {
  const RootLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: BottomNavigationBar(
        items: [
          for (final x in _items)
            BottomNavigationBarItem(
              label: x.name,
              icon: ImageIcon(AssetImage(x.icon)),
              activeIcon: ImageIcon(AssetImage(x.activeIcon)),
            ),
        ],
      ),
    );
  }
}
