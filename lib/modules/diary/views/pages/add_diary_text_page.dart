import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

/// A writing surface for a new diary item. Drafts stay on this route only.
class AddDiaryTextPage extends StatelessWidget {
  const AddDiaryTextPage({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    appBar: AppBar(
      leading: const BackButton(),
      title: const Text('Add text'),
      backgroundColor: context.colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: CustomPaint(
              painter: DiaryPaperStamp(
                paper: context.colors.surfaceContainerLowest,
                ink: context.colors.onSurface,
                shadowColor: context.colors.shadow,
                variant: date.weekday,
                edgeScale: .5,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            TimeHelper.format(
                              date,
                              pattern: TimeFormat.shortWeekdayDate,
                              locale: Localizations.localeOf(context)
                                  .toString(),
                              toLocal: false,
                            ),
                            style: TextStyle(
                              color: context.colors.onSurfaceVariant,
                              fontSize: 12,
                              letterSpacing: .5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            key: const ValueKey('diary-text-editor'),
                            autofocus: true,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            textCapitalization: TextCapitalization.sentences,
                            minLines: 10,
                            maxLines: null,
                            style: TextStyle(
                              color: context.colors.onSurface,
                              fontSize: 18,
                              height: 1.7,
                            ),
                            cursorColor: context.colors.primary,
                            decoration: InputDecoration(
                              hintText: 'Start writing about your day…',
                              hintStyle: TextStyle(
                                color: context.colors.onSurfaceVariant,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
