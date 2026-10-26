import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

/// A writing surface that commits a diary item and its sync outbox together.
class AddDiaryTextPage extends StatefulWidget {
  const AddDiaryTextPage({super.key, required this.date});

  final DateTime date;

  @override
  State<AddDiaryTextPage> createState() => _AddDiaryTextPageState();
}

class _AddDiaryTextPageState extends State<AddDiaryTextPage> {
  final _text = TextEditingController();
  bool _saved = false;
  DateTime get date => widget.date;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_saved || _text.text.trim().isEmpty) return;
    try {
      ProviderScope.containerOf(context, listen: false)
          .read(diaryRepositoryProvider)
          .addTimelineItem(
            dateString: TimeHelper.dateKey(date),
            content: _text.text.trim(),
          );
      _saved = true;
      context.nav.pop();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : 'Could not save your diary. Your draft is still here.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    appBar: AppBar(
      leading: const BackButton(),
      title: const Text('Add text'),
      actions: [
        TextButton(
          key: const ValueKey('save-diary-text'),
          onPressed: _text.text.trim().isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ],
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
                            controller: _text,
                            onChanged: (_) => setState(() {}),
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
