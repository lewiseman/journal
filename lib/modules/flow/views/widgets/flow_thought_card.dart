import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:journal/common.dart';

const _papers = [
  NoteColorPreset.sand,
  NoteColorPreset.lavender,
  NoteColorPreset.sage,
  NoteColorPreset.rose,
  NoteColorPreset.sky,
  NoteColorPreset.paper,
];

int _paperIndex(ThoughtEntity thought) => thought.uuid.codeUnits.fold(
  0,
  (sum, unit) => (sum + unit) % _papers.length,
);

NoteColors flowThoughtColors(ThoughtEntity thought, ColorScheme colors) =>
    _papers[_paperIndex(thought)].resolveColors(colors);

String flowThoughtDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return DateFormat(date.year == now.year ? 'MMM d' : 'MMM d, y').format(date);
}

class FlowThoughtCard extends StatelessWidget {
  const FlowThoughtCard({
    super.key,
    required this.thought,
    required this.onTap,
  });

  final ThoughtEntity thought;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = flowThoughtColors(thought, context.colors);
    final alternate = _paperIndex(thought).isOdd;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(alternate ? 25 : 17),
      topRight: Radius.circular(alternate ? 17 : 25),
      bottomLeft: const Radius.circular(22),
      bottomRight: Radius.circular(alternate ? 28 : 16),
    );
    final date = flowThoughtDate(thought.createdAt);
    return Semantics(
      button: true,
      label: '$date. ${thought.content}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: colors.background,
        elevation: 2,
        shadowColor: context.colors.shadow.withValues(alpha: .16),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.foreground.withValues(alpha: .07)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onTap,
          splashColor: colors.foreground.withValues(alpha: .08),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final compact = constraints.maxHeight < 100 * scale;
              final padding = compact ? 12.0 : 16.0;
              final fontSize = compact ? 14.0 : 16.0;
              final lineHeight =
                  MediaQuery.textScalerOf(context).scale(fontSize) * 1.4;
              final metadataHeight = compact ? 0.0 : 25 * scale;
              final lines = math.max(
                1,
                ((constraints.maxHeight - padding * 2 - metadataHeight) /
                        lineHeight)
                    .floor(),
              );
              return Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact) ...[
                      Text(
                        date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.secondary.withValues(alpha: .8),
                          letterSpacing: .2,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Expanded(
                      child: Text(
                        thought.content,
                        maxLines: lines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.foreground,
                          fontSize: fontSize,
                          height: 1.4,
                          letterSpacing: -.2,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
