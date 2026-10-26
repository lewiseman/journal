import 'package:journal/common.dart';

class TasksPreviewCard extends StatelessWidget {
  const TasksPreviewCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final paper = Color.alphaBlend(
      colors.primary.withValues(alpha: context.isDark ? .10 : .055),
      colors.surface,
    );

    return Material(
      key: const ValueKey('more-tasks-preview'),
      color: paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colors.primary.withValues(alpha: .14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.checklist_rounded,
                    color: colors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Tasks',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: .65),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '0 to do',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: colors.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              Text(
                'One thing at a time.',
                style: TextStyle(
                  fontSize: 27,
                  height: 1.15,
                  letterSpacing: -.9,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A place for the little things you want to do.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 18),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 27,
                      color: colors.primary.withValues(alpha: .65),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Your tasks will live here.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.primary.withValues(alpha: .13)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 17),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'View all tasks',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
