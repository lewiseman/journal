import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/flow/views/widgets/flow_reflection.dart';
import 'package:journal/modules/flow/views/widgets/flow_thought_card.dart';

/// An opened Flow thought on a page of its own, in the thought's paper
/// colour, with its optional reflection beneath it.
class FlowThoughtPage extends StatelessWidget {
  const FlowThoughtPage({super.key, required this.thought});

  final ThoughtEntity thought;

  @override
  Widget build(BuildContext context) {
    final paper = flowThoughtColors(thought, context.colors);
    final background = paper.background;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: paper.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            (ThemeData.estimateBrightnessForColor(background) ==
                        Brightness.dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
        toolbarHeight: 64,
        leading: Center(
          child: IconButton(
            tooltip: 'Back',
            onPressed: () => context.nav.maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: paper.foreground.withValues(alpha: .08),
              foregroundColor: paper.foreground,
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR THOUGHT',
                    style: TextStyle(
                      color: paper.secondary,
                      fontSize: 10,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    DateFormat(
                      'EEEE, MMMM d · h:mm a',
                    ).format(thought.createdAt),
                    style: TextStyle(color: paper.secondary, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  SelectableText(
                    thought.content,
                    style: TextStyle(
                      fontSize: 23,
                      height: 1.5,
                      letterSpacing: -.4,
                      color: paper.foreground,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FlowReflection(thought: thought, paper: paper),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
