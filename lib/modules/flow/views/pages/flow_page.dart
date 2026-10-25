import 'package:journal/common.dart';

class FlowPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          bottom: 120,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: const TransparentVideoPlayer(
                    assetPath: 'assets/videos/reflecting.mp4',
                    stackedAlpha: true,
                  ),
                ),
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 50,
          left: 50,
          right: 50,
          child: Row(
            children: [
              const Expanded(
                child: TextField(
                  decoration: InputDecoration(hintText: 'Flow with it ...'),
                ),
              ),
              IconButton(onPressed: () {}, icon: const Icon(Icons.mic)),
            ],
          ),
        ),
      ],
    );
  }
}
