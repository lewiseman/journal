import 'package:flutter/material.dart';

class DiaryPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final artworkWidth = width.clamp(0.0, 700.0);
    return Stack(
      children: [
        Positioned(
          top: 100 - artworkWidth * .41,
          left: (width - artworkWidth) / 2,
          width: artworkWidth,
          child: Image.asset('assets/images/diary_top_bg.png'),
        ),
      ],
    );
  }
}
