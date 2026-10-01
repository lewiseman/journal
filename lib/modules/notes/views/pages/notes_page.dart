import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      itemCount: 5,
      padding: EdgeInsets.only(left: 16, right: 16, bottom: 100),
      itemBuilder: (context, index) {
        return Container(color: Colors.red, height: 200);
      },
    );
  }
}
