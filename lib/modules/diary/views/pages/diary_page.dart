import 'package:flutter/material.dart';

class DiaryPage extends StatelessWidget {
  const DiaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: BouncingScrollPhysics(),
      reverse: true,
      padding: EdgeInsets.only(bottom: 150),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Image.asset('assets/images/icons/plus_brown.png', height: 65);
        }
        return ListTile(title: Text('data'));
      },
    );
  }
}
