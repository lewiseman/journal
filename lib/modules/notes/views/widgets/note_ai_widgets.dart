import 'package:flutter/material.dart';
import 'package:journal/modules/assistant/qvac_assistant.dart';

/// One visual language from the note toolbox through to the reviewed result.
enum NoteAiTool {
  ideas(
    'Note ideas',
    'Choose a topic to get note ideas.',
    'Note ideas',
    'Start a new note',
    Color(0xFFB5683F),
  ),
  search(
    'AI note search',
    'Ask a question and get an answer from your notes.',
    'AI note search',
    'Ask about your notes',
    Color(0xFF527C9C),
  ),
  template(
    'Starting template',
    'Choose a template for your note.',
    'Start a note',
    'Choose a template',
    Color(0xFFB5683F),
  ),
  summary(
    'Note summary',
    'Turn a long note into a few clear lines.',
    'Shorten',
    'Keep the key points',
    Color(0xFF44766B),
  ),
  writing(
    'Writing help',
    'Choose how you want to improve your note.',
    'Improve writing',
    'Rewrite, expand, or edit',
    Color(0xFF75619B),
  ),
  metadata(
    'Title & tag ideas',
    'Pick a title and tags to find it again.',
    'Name & sort',
    'Title and tag ideas',
    Color(0xFFB5683F),
  ),
  image(
    'Ask about an image',
    'Choose a photo. Ask or read what is in it.',
    'Explore a photo',
    'See details, read text',
    Color(0xFF527C9C),
  ),
  scan(
    'Scan a page',
    'Take a photo. Check the words. Add them.',
    'Read a page',
    'Photo to written words',
    Color(0xFF527C9C),
  ),
  background(
    'Generate a background',
    'Choose a preset or describe a background.',
    'Add a backdrop',
    'Generate a background',
    Color(0xFF9C6887),
  ),
  presentation(
    'Presentation',
    'Choose a website or format your note.',
    'Style this note',
    'Website or formatted text',
    Color(0xFF75619B),
  );

  const NoteAiTool(
    this.title,
    this.description,
    this.label,
    this.caption,
    this.tint,
  );
  final String title, description, label, caption;
  final Color tint;

  Color ink(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(tint, Colors.white, .42)!
      : tint;
}

Color noteAiPaper(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF232522)
    : const Color(0xFFFAF8F2);

/// Illustrated choices retain their meaning without depending on color alone.
class NoteAiArt extends StatelessWidget {
  const NoteAiArt({super.key, required this.tool, this.size = 64});
  final NoteAiTool tool;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ToolPainter(tool, tool.ink(context), noteAiPaper(context)),
      ),
    ),
  );
}

class _ToolPainter extends CustomPainter {
  const _ToolPainter(this.tool, this.ink, this.paper);
  final NoteAiTool tool;
  final Color ink, paper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 80, size.height / 80);
    final stroke = Paint()
      ..color = ink
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = ink.withValues(alpha: .12);
    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x, y), Offset(x2, y2), stroke);
    void sheet(double x, double y, double w, double h, {bool tinted = false}) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect.shift(const Offset(3, 4)), fill);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = tinted
              ? Color.alphaBlend(ink.withValues(alpha: .08), paper)
              : paper,
      );
      canvas.drawRRect(rect, stroke);
    }

    void lines(double x, double y, double w, int count) {
      for (var i = 0; i < count; i++) {
        line(x, y + i * 7, x + w * (i == count - 1 ? .65 : 1), y + i * 7);
      }
    }

    void sparkle(double x, double y) {
      final path = Path()
        ..moveTo(x, y - 6)
        ..quadraticBezierTo(x + 1, y - 1, x + 6, y)
        ..quadraticBezierTo(x + 1, y + 1, x, y + 6)
        ..quadraticBezierTo(x - 1, y + 1, x - 6, y)
        ..quadraticBezierTo(x - 1, y - 1, x, y - 6)
        ..close();
      canvas.drawPath(path, Paint()..color = ink);
    }

    switch (tool) {
      case NoteAiTool.summary:
        sheet(8, 12, 32, 49);
        lines(15, 23, 18, 4);
        sheet(38, 31, 33, 34, tinted: true);
        lines(45, 43, 18, 2);
        line(48, 17, 66, 17);
        line(61, 12, 66, 17);
        line(61, 22, 66, 17);
      case NoteAiTool.writing:
        sheet(13, 16, 43, 49);
        lines(21, 29, 25, 3);
        canvas.save();
        canvas.translate(53, 41);
        canvas.rotate(.62);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-4, -23, 8, 35),
            const Radius.circular(2),
          ),
          Paint()..color = ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(-4, 14)
            ..lineTo(0, 22)
            ..lineTo(4, 14)
            ..close(),
          Paint()..color = ink,
        );
        canvas.restore();
        sparkle(64, 15);
      case NoteAiTool.metadata:
        sheet(11, 13, 48, 48);
        final titlePaint = Paint()
          ..color = ink
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(20, 26), const Offset(47, 26), titlePaint);
        lines(20, 38, 25, 2);
        final tag = Path()
          ..moveTo(37, 51)
          ..lineTo(58, 51)
          ..lineTo(70, 61)
          ..lineTo(58, 71)
          ..lineTo(37, 71)
          ..close();
        canvas.drawPath(tag, Paint()..color = paper);
        canvas.drawPath(tag, stroke);
        canvas.drawCircle(const Offset(59, 61), 2.5, Paint()..color = ink);
      case NoteAiTool.image:
      case NoteAiTool.background:
        sheet(10, 18, 53, 43, tinted: true);
        canvas.drawCircle(
          const Offset(47, 30),
          5,
          Paint()..color = ink.withValues(alpha: .6),
        );
        final hills = Path()
          ..moveTo(15, 54)
          ..lineTo(29, 36)
          ..lineTo(41, 48)
          ..lineTo(49, 42)
          ..lineTo(59, 54);
        canvas.drawPath(hills, stroke);
        if (tool == NoteAiTool.image) {
          canvas.drawCircle(const Offset(59, 57), 11, Paint()..color = paper);
          canvas.drawCircle(const Offset(59, 57), 11, stroke);
          line(67, 65, 74, 72);
        } else {
          sparkle(66, 16);
          sparkle(65, 66);
        }
      case NoteAiTool.scan:
        sheet(22, 14, 36, 51);
        lines(29, 29, 22, 4);
        line(10, 27, 10, 10);
        line(10, 10, 27, 10);
        line(53, 10, 70, 10);
        line(70, 10, 70, 27);
        line(10, 53, 10, 70);
        line(10, 70, 27, 70);
        line(53, 70, 70, 70);
        line(70, 70, 70, 53);
        canvas.drawRect(const Rect.fromLTWH(6, 37, 68, 7), fill);
        line(6, 40, 74, 40);
      case NoteAiTool.presentation:
        sheet(9, 15, 61, 49);
        line(9, 25, 70, 25);
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(16 + i * 6, 20), 1.5, Paint()..color = ink);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(16, 32, 22, 24),
            const Radius.circular(2),
          ),
          fill,
        );
        lines(44, 34, 18, 3);
        sparkle(64, 63);
      case NoteAiTool.ideas:
        sheet(10, 28, 39, 39);
        lines(17, 40, 22, 3);
        canvas.drawCircle(const Offset(54, 26), 13, Paint()..color = paper);
        canvas.drawCircle(const Offset(54, 26), 13, stroke);
        line(48, 39, 60, 39);
        line(49, 44, 59, 44);
        line(54, 8, 54, 3);
        line(72, 26, 77, 26);
        line(69, 12, 73, 8);
        sparkle(69, 53);
      case NoteAiTool.search:
        sheet(12, 11, 39, 50);
        sheet(18, 17, 39, 50, tinted: true);
        lines(25, 30, 23, 3);
        canvas.drawCircle(const Offset(58, 51), 12, Paint()..color = paper);
        canvas.drawCircle(const Offset(58, 51), 12, stroke);
        line(67, 60, 75, 68);
        sparkle(66, 13);
      case NoteAiTool.template:
        sheet(14, 12, 49, 57);
        line(23, 25, 49, 25);
        for (var i = 0; i < 3; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(23, 35 + i * 9, 4, 4),
              const Radius.circular(1),
            ),
            stroke,
          );
          line(33, 37 + i * 9, 53, 37 + i * 9);
        }
        sparkle(65, 16);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ToolPainter oldDelegate) =>
      oldDelegate.tool != tool ||
      oldDelegate.ink != ink ||
      oldDelegate.paper != paper;
}

class NoteAiToolCard extends StatelessWidget {
  const NoteAiToolCard({
    super.key,
    required this.tool,
    required this.onTap,
    this.horizontal = false,
  });
  final NoteAiTool tool;
  final VoidCallback? onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final ink = tool.ink(context);
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tool.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          tool.caption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      excludeSemantics: true,
      enabled: onTap != null,
      label: '${tool.label}. ${tool.caption}',
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Material(
          color: Color.alphaBlend(
            ink.withValues(alpha: .07),
            noteAiPaper(context),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: ink.withValues(alpha: .18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            excludeFromSemantics: true,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: horizontal
                  ? Row(
                      children: [
                        NoteAiArt(tool: tool, size: 52),
                        const SizedBox(width: 12),
                        Expanded(child: text),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: ink),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            NoteAiArt(tool: tool, size: 52),
                            const Spacer(),
                            Icon(
                              Icons.arrow_outward_rounded,
                              size: 18,
                              color: ink,
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        text,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Content shares the sheet scroll position; back stays within reach.
class NoteAiScaffold extends StatelessWidget {
  const NoteAiScaffold({
    super.key,
    required this.tool,
    required this.children,
    this.step = 0,
    this.listKey,
    this.header,
    this.loading,
  });
  final NoteAiTool tool;
  final List<Widget> children;
  final int step;
  final Key? listKey;
  final Widget? header;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final ink = tool.ink(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final theme = base.copyWith(
      scaffoldBackgroundColor: noteAiPaper(context),
      colorScheme: base.colorScheme.copyWith(
        primary: ink,
        primaryContainer: Color.alphaBlend(
          ink.withValues(alpha: .14),
          noteAiPaper(context),
        ),
        onPrimaryContainer: ink,
        surface: noteAiPaper(context),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: base.brightness == Brightness.dark
              ? const Color(0xFF1C211E)
              : Colors.white,
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 50),
          shape: shape,
          side: BorderSide(color: ink.withValues(alpha: .3)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Color.alphaBlend(
          ink.withValues(alpha: .025),
          noteAiPaper(context),
        ),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: ink.withValues(alpha: .22)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: ink.withValues(alpha: .22)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: ink, width: 2),
        ),
      ),
    );
    return QvacAssistantSheetPage(
      child: Theme(
        data: theme,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const BackButton(),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          tool.title,
                          style: base.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      key: listKey,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        if (loading != null)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight > 32
                                  ? constraints.maxHeight - 32
                                  : 0,
                            ),
                            child: Center(child: loading),
                          )
                        else ...[
                          const SizedBox(height: 8),
                          if (header != null)
                            header!
                          else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                NoteAiArt(
                                  tool: tool,
                                  size: largeText ? 48 : 56,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    tool.description,
                                    style: base.textTheme.bodyMedium?.copyWith(
                                      height: 1.35,
                                      color: base.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _StepTrail(step: step, ink: ink),
                          ],
                          const SizedBox(height: 20),
                          ...children,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepTrail extends StatelessWidget {
  const _StepTrail({required this.step, required this.ink});
  final int step;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    const labels = ['Choose', 'Create', 'Review'];
    final active = step.clamp(0, 2);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    return Semantics(
      label: 'Step ${active + 1} of 3: ${labels[active]}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: ink.withValues(alpha: .45),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          height: 30,
                          width: 38,
                          decoration: BoxDecoration(
                            color: ink.withValues(
                              alpha: i == active ? .16 : .04,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            i < active
                                ? Icons.check_rounded
                                : [
                                    Icons.touch_app_outlined,
                                    Icons.auto_awesome_outlined,
                                    Icons.fact_check_outlined,
                                  ][i],
                            size: 19,
                            color: ink.withValues(alpha: i <= active ? 1 : .45),
                          ),
                        ),
                        if (!largeText) ...[
                          const SizedBox(height: 4),
                          Text(
                            labels[i],
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: i == active
                                      ? ink
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  fontWeight: i == active
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (largeText)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  labels[active],
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: ink, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NoteAiDetails extends StatelessWidget {
  const NoteAiDetails(this.text, {super.key, required this.title});
  final String text, title;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    shape: const Border(),
    collapsedShape: const Border(),
    leading: const Icon(Icons.info_outline_rounded, size: 19),
    title: Text(title, style: Theme.of(context).textTheme.bodySmall),
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
        ),
      ),
    ],
  );
}

class NoteAiPreview extends StatelessWidget {
  const NoteAiPreview({
    super.key,
    required this.child,
    this.label = 'Your preview',
  });
  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 12),
        Text(
          'Check the details before you keep them.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

/// Wrapping choices never squeeze or truncate labels at large text sizes.
class NoteAiChoices<T> extends StatelessWidget {
  const NoteAiChoices({
    super.key,
    required this.choices,
    required this.selected,
    required this.onChanged,
    this.icons = const {},
  });
  final Map<T, String> choices;
  final T selected;
  final ValueChanged<T>? onChanged;
  final Map<T, IconData> icons;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final choice in choices.entries)
          Semantics(
            button: true,
            selected: selected == choice.key,
            child: ChoiceChip(
              label: Text(choice.value),
              avatar: selected == choice.key
                  ? const Icon(Icons.check_rounded, size: 19)
                  : icons[choice.key] == null
                  ? null
                  : Icon(icons[choice.key], size: 19),
              selectedColor: Color.alphaBlend(
                Theme.of(context).colorScheme.primary.withValues(alpha: .14),
                noteAiPaper(context),
              ),
              backgroundColor: noteAiPaper(context),
              selected: selected == choice.key,
              onSelected: onChanged == null
                  ? null
                  : (_) => onChanged!(choice.key),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: selected == choice.key ? .7 : .2),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Concrete starting points let a person choose a picture before typing.
class NoteAiBackdropIdeas extends StatelessWidget {
  const NoteAiBackdropIdeas({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String>? onChanged;

  static const _ideas = [
    (
      'Ocean',
      'Soft ocean waves and sea glass, calm and minimal',
      Icons.waves_rounded,
      Color(0xFF527C9C),
    ),
    (
      'Leaves',
      'Soft green leaves on warm paper, calm and minimal',
      Icons.spa_outlined,
      Color(0xFF44766B),
    ),
    (
      'Sunset',
      'A warm peach sunset with soft clouds, calm and minimal',
      Icons.wb_twilight_rounded,
      Color(0xFFB5683F),
    ),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final idea in _ideas)
          ChoiceChip(
            selectedColor: Color.alphaBlend(
              Theme.of(context).colorScheme.primary.withValues(alpha: .14),
              noteAiPaper(context),
            ),
            backgroundColor: noteAiPaper(context),
            selected: value == idea.$2,
            label: Text(idea.$1),
            avatar: Icon(
              value == idea.$2 ? Icons.check_rounded : idea.$3,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Color.lerp(idea.$4, Colors.white, .4)
                  : idea.$4,
              size: 24,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: onChanged == null ? null : (_) => onChanged!(idea.$2),
          ),
      ],
    ),
  );
}
