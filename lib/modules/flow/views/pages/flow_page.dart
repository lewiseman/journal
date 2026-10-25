import 'package:flutter/material.dart';
import 'package:journal/common.dart';


class FlowPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          bottom: 50,
          left: 50,
          right: 50,
          child: Row(
            children: [
              Expanded(child: TextField()),
              IconButton(onPressed: () {}, icon: Icon(Icons.mic)),
            ],
          ),
        ),
      ],
    );
  }
}
