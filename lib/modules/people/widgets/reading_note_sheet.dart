import 'package:flutter/material.dart';

import 'people_paper.dart';

/// Brief notes sit in the middle of a full sheet. Longer letters grow naturally.
class ReadingNoteSheet extends StatelessWidget {
  const ReadingNoteSheet({
    super.key,
    required this.text,
    required this.minHeight,
  });

  final String text;
  final double minHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const padding = EdgeInsets.all(28);
      const fontSize = 18.0;
      const lineHeight = 30.0;
      final body = peopleBody(context, size: fontSize);
      final strut = StrutStyle(
        fontFamily: body.fontFamily,
        fontSize: fontSize,
        height: lineHeight / fontSize,
        forceStrutHeight: true,
      );
      final measure = TextPainter(
        text: TextSpan(text: text, style: body),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        strutStyle: strut,
      )..layout(maxWidth: constraints.maxWidth - padding.horizontal);
      final centered = measure.height <= minHeight - padding.vertical;
      measure.dispose();
      return PaperSheet(
        key: const ValueKey('people-reading-paper'),
        ruled: !centered,
        lineHeight:
            MediaQuery.textScalerOf(context).scale(fontSize) *
            lineHeight /
            fontSize,
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight - padding.vertical),
          child: Align(
            alignment: centered ? Alignment.center : Alignment.topLeft,
            child: Text(
              text,
              key: const ValueKey('people-reading-text'),
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: body,
              strutStyle: strut,
            ),
          ),
        ),
      );
    },
  );
}
