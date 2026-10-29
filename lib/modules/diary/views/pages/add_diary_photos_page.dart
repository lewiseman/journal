import 'dart:async';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_photo_stories.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/models/diary_photo.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_contract.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_controller.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_memory_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_contact_sheet.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_entry_book.dart';
import 'package:journal/modules/diary/views/widgets/diary_reflection_desk.dart';

enum _PhotoStage { photos, reflect, review }

// The usual questions, used until the person asks their computer about a
// photo, and whenever it isn't available. Same order as [diaryPhotoGroups].
const _usualQuestions = [
  [
    'What made you want to capture this moment?',
    'What was happening just before you took this photo?',
    'What happened after you put the camera away?',
  ],
  [
    'What were you feeling that the photo doesn’t show?',
    'How did this moment change the rhythm of your day?',
    'If you could step back into this moment, how would it feel?',
  ],
  [
    'What’s one thing outside the frame you want to remember?',
    'What could you hear, smell, or taste in this moment?',
    'Who or what made this moment feel like yours?',
  ],
];

typedef _Question = ({String text, bool fromPhoto});

class _PhotoMoment {
  _PhotoMoment({required this.path, required this.draft, required int seed})
    : variants = [seed % 3, seed % 3, seed % 3];

  /// Picker path for a new photo, saved path for a reopened one.
  final String path;
  final DiaryPhotoDraft draft;
  Uint8List get bytes => draft.bytes;
  String get sha => draft.sha256;
  final caption = TextEditingController();

  /// What the computer saw, editable, saved only when [keepSeen] is on.
  final seen = TextEditingController();
  bool keepSeen = false;
  final answers = <String, TextEditingController>{};

  /// Which group each question belongs to and where it came from, so
  /// answers keep their place when questions change.
  final meta = <String, ({int group, bool fromPhoto})>{};

  /// New questions from shuffle, per group, kept while the story is open.
  final extra = [<String>[], <String>[], <String>[]];

  /// Shuffle results already added, by the task that wrote them.
  final applied = <String>{};
  final List<int> variants;
  int group = 0;

  /// The questions for each group: from the photo when the computer wrote
  /// some, else the usual ones; answered questions are always kept.
  List<List<_Question>> groups(DiaryPhotoQuestions? generated) => [
    for (var g = 0; g < diaryPhotoGroups.length; g++)
      () {
        final base = <_Question>[
          for (final text in generated?.groups[g] ?? _usualQuestions[g])
            (text: text, fromPhoto: generated != null),
        ];
        for (final text in extra[g]) {
          if (!base.any((q) => q.text == text)) {
            base.add((text: text, fromPhoto: true));
          }
        }
        final shown = {for (final q in base) q.text};
        return [
          ...base,
          for (final answer in writtenAnswers)
            if (meta[answer.key]?.group == g && !shown.contains(answer.key))
              (text: answer.key, fromPhoto: meta[answer.key]!.fromPhoto),
        ];
      }(),
  ];

  _Question question(DiaryPhotoQuestions? generated) {
    final list = groups(generated)[group];
    return list[variants[group] % list.length];
  }

  TextEditingController answer(DiaryPhotoQuestions? generated) {
    final q = question(generated);
    meta.putIfAbsent(q.text, () => (group: group, fromPhoto: q.fromPhoto));
    return answers.putIfAbsent(q.text, TextEditingController.new);
  }

  Iterable<MapEntry<String, TextEditingController>> get writtenAnswers =>
      answers.entries.where((entry) => entry.value.text.trim().isNotEmpty);

  bool groupHasWords(int g) =>
      writtenAnswers.any((answer) => meta[answer.key]?.group == g);

  void dispose() {
    caption.dispose();
    seen.dispose();
    for (final answer in answers.values) {
      answer.dispose();
    }
  }
}

/// Builds or reopens a photo story. Only Save writes to the diary; closing
/// or going back leaves the diary and its saved photos untouched.
class AddDiaryPhotosPage extends ConsumerStatefulWidget {
  const AddDiaryPhotosPage({
    super.key,
    required this.date,
    this.story,
    this.readOnly = false,
    this.imagePicker,
  });

  final DateTime date;

  /// A saved photo story to reopen at its entry.
  final DiaryItem? story;

  /// Secondary devices can view saved stories but not change them.
  final bool readOnly;
  final Future<List<XFile>> Function()? imagePicker;

  @override
  ConsumerState<AddDiaryPhotosPage> createState() => _AddDiaryPhotosPageState();
}

class _AddDiaryPhotosPageState extends ConsumerState<AddDiaryPhotosPage> {
  final _moments = <_PhotoMoment>[];
  final _pages = PageController(keepPage: false);
  final _rail = ScrollController();
  final _scroll = ScrollController();
  final _questionAnchor = GlobalKey();
  _PhotoStage _stage = _PhotoStage.photos;
  _PhotoStage _reviewFrom = _PhotoStage.photos;
  int _selected = 0;
  bool _picking = false;
  bool _saving = false;
  bool _opening = false;
  bool _includeReflections = true;
  bool _editingPhotos = false;
  bool get _reopened => widget.story != null;
  bool get _canReturnToEntry =>
      (_editingPhotos || _reopened) && _moments.isNotEmpty;

  /// The stage the close button belongs to; elsewhere it goes back.
  bool get _atHome => _reopened
      ? _stage == _PhotoStage.review || _moments.isEmpty
      : _stage == _PhotoStage.photos && !_canReturnToEntry;
  String? _pickerError;

  _PhotoMoment get _moment => _moments[_selected];
  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void initState() {
    super.initState();
    if (_reopened) {
      _stage = _PhotoStage.review;
      _opening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickPhotos();
      });
    }
  }

  DiaryPhotoStories get _stories => ref.read(diaryPhotoStoriesProvider);

  /// Generated questions for [moment], when the computer wrote some.
  DiaryPhotoQuestions? _generated(_PhotoMoment moment) =>
      _photoQuestions?.questions[moment.sha];

  /// Watched only once the person reaches Reflect, so building or
  /// reopening a story never starts the companion.
  DiaryPhotoQuestionState? _photoQuestions;

  Future<void> _open() async {
    if (!mounted) return;
    final story = widget.story!;
    final drafts = await _stories.open(story);
    if (!mounted) return;
    setState(() {
      for (final (index, photo) in story.photos.indexed) {
        final moment = _PhotoMoment(
          path: photo.path,
          draft: drafts[index],
          seed: index,
        );
        moment.caption.text = photo.caption;
        moment.seen.text = photo.seen;
        moment.keepSeen = photo.seen.isNotEmpty;
        for (final reflection in photo.reflections) {
          moment.answers[reflection.question] = TextEditingController(
            text: reflection.answer,
          );
          final named = diaryPhotoGroups.indexWhere(
            (group) => group.key == reflection.group,
          );
          // Answers saved before I02 carry no group: find their usual one.
          final group = named >= 0
              ? named
              : _usualQuestions.indexWhere(
                  (questions) => questions.contains(reflection.question),
                );
          if (group >= 0) {
            moment.meta[reflection.question] = (
              group: group,
              fromPhoto: reflection.fromPhoto,
            );
          }
        }
        _moments.add(moment);
      }
      _opening = false;
    });
  }

  Future<void> _save() async {
    if (_saving || _moments.isEmpty || widget.readOnly) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _stories.save(
        dateString: TimeHelper.dateKey(widget.date),
        existingItemUuid: widget.story?.itemUuid,
        newItemUuid: _newItemUuid,
        photos: [
          for (final moment in _moments)
            (
              draft: moment.draft,
              caption: moment.caption.text,
              reflections: [
                if (_includeReflections)
                  for (final answer in moment.writtenAnswers)
                    DiaryPhotoReflection(
                      question: answer.key,
                      answer: answer.value.text,
                      group: switch (moment.meta[answer.key]?.group) {
                        final int g => diaryPhotoGroups[g].key,
                        null => '',
                      },
                      fromPhoto: moment.meta[answer.key]?.fromPhoto ?? false,
                    ),
              ],
              seen: _includeReflections && moment.keepSeen
                  ? moment.seen.text
                  : '',
            ),
        ],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : 'Your photo story couldn’t be saved. It’s still here.',
          ),
        ),
      );
    }
  }

  // One identity per new story, so a retried save can't add it twice.
  late final _newItemUuid = const Uuid().v4();

  @override
  void dispose() {
    _pages.dispose();
    _rail.dispose();
    _scroll.dispose();
    for (final moment in _moments) {
      moment.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    if (_picking) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _picking = true;
      _pickerError = null;
    });
    try {
      final files =
          await (widget.imagePicker?.call() ??
              ImagePicker().pickMultiImage(
                maxWidth: 1800,
                maxHeight: 1800,
                imageQuality: 85,
                requestFullMetadata: false,
              ));
      if (!mounted) return;
      final paths = _moments.map((moment) => moment.path).toSet();
      final hashes = {
        for (final moment in _moments)
          if (moment.draft.sha256.isNotEmpty) moment.draft.sha256,
      };
      final added = <_PhotoMoment>[];
      var unreadable = 0;
      for (final file in files) {
        if (!paths.add(file.path)) continue;
        try {
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) throw const FormatException('Empty photo');
          final sha256 = await DiaryPhotoStore.digest(bytes);
          if (!hashes.add(sha256)) continue;
          added.add(
            _PhotoMoment(
              path: file.path,
              draft: DiaryPhotoDraft(
                bytes: bytes,
                sha256: sha256,
                sourceExtension: p.extension(file.path),
              ),
              seed: _moments.length + added.length,
            ),
          );
        } catch (_) {
          unreadable++;
        }
      }
      if (!mounted) {
        for (final moment in added) {
          moment.dispose();
        }
        return;
      }
      setState(() {
        _moments.addAll(added);
        if (unreadable > 0) {
          _pickerError =
              'Some photos couldn’t be opened. Try choosing them again.';
        }
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _pickerError =
            error.code.contains('denied') || error.code.contains('restricted')
            ? 'Photo access is off. You can allow it in your device settings, then try again.'
            : 'Your photos couldn’t be opened. Please try again.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _pickerError =
              'Your photos couldn’t be opened. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _changeStage(_PhotoStage stage) {
    FocusScope.of(context).unfocus();
    setState(() => _stage = stage);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (stage == _PhotoStage.photos && _pages.hasClients) {
        _pages.jumpToPage(_selected);
      }
      _scrollRail();
      _revealQuestion();
    });
  }

  void _revealQuestion() {
    if (_stage != _PhotoStage.reflect) return;
    final compact =
        MediaQuery.sizeOf(context).height < 550 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final anchor = _questionAnchor.currentContext;
    if (compact && anchor != null) {
      Scrollable.ensureVisible(anchor, alignment: .05);
    }
  }

  void _selectPhoto(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _selected = index);
    if (_pages.hasClients) {
      if (_reduced) {
        _pages.jumpToPage(index);
      } else {
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    }
    _scrollRail();
  }

  void _scrollRail() {
    if (!_rail.hasClients) return;
    final target = (_selected * 74.0 - 80).clamp(
      0.0,
      _rail.position.maxScrollExtent,
    );
    if (_reduced) {
      _rail.jumpTo(target);
    } else {
      _rail.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _removePhoto(int index) {
    FocusScope.of(context).unfocus();
    final removed = _moments[index];
    setState(() {
      _moments.removeAt(index);
      _selected = _moments.isEmpty
          ? 0
          : _selected.clamp(0, _moments.length - 1);
    });
    // Let the old caption field detach before disposing its controller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      removed.dispose();
      if (!mounted) return;
      if (_moments.isNotEmpty && _pages.hasClients) {
        _pages.jumpToPage(_selected);
      }
      _scrollRail();
    });
  }

  void _review({required bool includeReflections}) {
    _reviewFrom = _stage;
    _includeReflections = includeReflections;
    _changeStage(_PhotoStage.review);
  }

  void _advance() {
    FocusScope.of(context).unfocus();
    if (_moment.group < diaryPhotoGroups.length - 1) {
      setState(() => _moment.group++);
    } else if (_selected < _moments.length - 1) {
      _selectPhoto(_selected + 1);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else {
      _review(includeReflections: true);
    }
  }

  void _back() {
    if (_atHome) {
      Navigator.pop(context);
    } else if (_stage == _PhotoStage.photos && _canReturnToEntry) {
      _finishEditingPhotos();
    } else {
      _changeStage(
        _stage == _PhotoStage.review ? _reviewFrom : _PhotoStage.photos,
      );
    }
  }

  void _editPhotos() {
    _editingPhotos = true;
    _changeStage(_PhotoStage.photos);
  }

  void _finishEditingPhotos() {
    _editingPhotos = false;
    _changeStage(_PhotoStage.review);
  }

  void _reorderPhoto(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    FocusScope.of(context).unfocus();
    final selected = _moment;
    setState(() {
      final moved = _moments.removeAt(oldIndex);
      _moments.insert(newIndex, moved);
      _selected = _moments.indexOf(selected);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pages.hasClients) _pages.jumpToPage(_selected);
      _scrollRail();
    });
  }

  void _showPhoto(_PhotoMoment moment, int index) {
    FocusScope.of(context).unfocus();
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: context.colors.surface,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: 'Close photo',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Expanded(
                child: Semantics(
                  label: 'Photo ${index + 1}',
                  image: true,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: DiaryPhotoImage(
                        bytes: moment.bytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Pinch to zoom',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _listenForReasons() => ref.listen(
    diaryPhotoQuestionProvider.select((state) => state.messages),
    (previous, next) {
      final mine = {for (final moment in _moments) moment.sha};
      final fresh = next.entries
          .where((e) => mine.contains(e.key) && previous?[e.key] != e.value)
          .map((e) => e.value)
          .toSet();
      if (fresh.isNotEmpty) _showReason(fresh.first);
    },
  );

  String? _shownReason;

  /// Why some photos kept the usual questions, shown once per reason.
  void _showReason(String reason) {
    if (!mounted || reason == _shownReason) return;
    _shownReason = reason;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('diary-photo-message'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(reason),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // A photo that got no questions keeps the usual ones; say why once.
    // Only on Reflect, so opening or saving a story never starts the AI.
    if (_stage == _PhotoStage.reflect) _listenForReasons();
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final background = DiaryMemoryPalette.of(context).desk;
    return PopScope(
      canPop: _atHome && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          leading: DiaryInkAction(
            label: _atHome ? _closeLabel : 'Back',
            tooltip: _atHome
                ? _closeLabel
                : _stage == _PhotoStage.photos
                ? 'Back to entry'
                : (_stage == _PhotoStage.review &&
                      _reviewFrom == _PhotoStage.reflect)
                ? 'Back to reflections'
                : 'Back to photos',
            onPressed: _saving ? null : _back,
            child: Center(
              child: Transform.flip(
                flipX: Directionality.of(context) == TextDirection.ltr,
                child: DiaryInkGlyph(
                  symbol: _atHome ? DiaryInkSymbol.close : DiaryInkSymbol.arrow,
                  color: DiaryMemoryPalette.of(context).ink,
                ),
              ),
            ),
          ),
          title: _sectionNavigation(),
          titleSpacing: 8,
          centerTitle: false,
          toolbarHeight: (MediaQuery.textScalerOf(context).scale(13) * 2.4 + 12)
              .clamp(56.0, double.infinity),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _dateLabel(),
                          const SizedBox(height: 16),
                          if (_stage == _PhotoStage.photos) _photos(),
                          if (_stage == _PhotoStage.reflect) _reflection(),
                          if (_stage == _PhotoStage.review) _entryPreview(),
                        ],
                      ),
                    ),
                  ),
                  if (!typing) _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _closeLabel =>
      widget.readOnly ? 'Close photo story' : 'Close without saving';

  bool _sectionEnabled(_PhotoStage stage) =>
      !_picking &&
      !_saving &&
      !_opening &&
      (stage == _PhotoStage.photos || _moments.isNotEmpty) &&
      (!widget.readOnly || stage == _PhotoStage.review);

  void _selectSection(_PhotoStage stage) {
    if (!_sectionEnabled(stage) || stage == _stage) return;
    if (stage != _PhotoStage.photos && _moments.isEmpty) return;
    switch (stage) {
      case _PhotoStage.photos:
        if (_stage == _PhotoStage.review) {
          _editPhotos();
        } else {
          _changeStage(stage);
        }
      case _PhotoStage.reflect:
        _editingPhotos = false;
        _changeStage(stage);
      case _PhotoStage.review:
        if (_stage == _PhotoStage.photos && _canReturnToEntry) {
          _finishEditingPhotos();
        } else {
          _review(includeReflections: true);
        }
    }
  }

  Widget _sectionNavigation() {
    final palette = DiaryMemoryPalette.of(context);
    return Row(
      children: [
        for (final (stage, label) in [
          (_PhotoStage.photos, 'Photos'),
          (_PhotoStage.reflect, 'Reflect'),
          (_PhotoStage.review, 'Entry'),
        ])
          Expanded(
            child: DiaryInkAction(
              key: ValueKey('diary-section-${stage.name}'),
              label: label,
              selected: _stage == stage,
              onPressed: _sectionEnabled(stage)
                  ? () => _selectSection(stage)
                  : null,
              child: CustomPaint(
                foregroundPainter: _stage == stage
                    ? DiaryInkUnderline(ink: palette.ink)
                    : null,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        fontStyle: FontStyle.italic,
                        color: _stage == stage ? palette.ink : palette.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dateLabel() => Text(
    TimeHelper.format(
      widget.date,
      pattern: TimeFormat.shortWeekdayDate,
      toLocal: false,
    ),
    style: TextStyle(
      fontSize: 10,
      letterSpacing: 1,
      color: context.colors.onSurfaceVariant,
    ),
  );

  Widget _photos() {
    final palette = DiaryMemoryPalette.of(context);
    if (_moments.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 20),
          const DiaryPhotoInvitation(),
          const SizedBox(height: 25),
          Text(
            'Select one or more photos.',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: palette.muted,
            ),
          ),
          if (_pickerError != null) ...[
            const SizedBox(height: 22),
            _errorNotice(),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final imageHeight = (constraints.maxWidth * .55).clamp(
              150.0,
              300.0,
            );
            final scale = MediaQuery.textScalerOf(context);
            final captionHeight = scale.scale(14) * 1.6 * 2 + 8;
            final labelHeight = (scale.scale(12) * 1.2 + 30).clamp(
              48.0,
              double.infinity,
            );
            return SizedBox(
              height: imageHeight + captionHeight + labelHeight + 45,
              child: PageView.builder(
                key: const ValueKey('diary-photo-pages'),
                controller: _pages,
                itemCount: _moments.length,
                onPageChanged: (index) {
                  setState(() => _selected = index);
                  _scrollRail();
                },
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: DiaryPhotoFrame(
                    bytes: _moments[index].bytes,
                    label: 'MOMENT ${(index + 1).toString().padLeft(2, '0')}',
                    height: imageHeight,
                    onTap: () => _showPhoto(_moments[index], index),
                    trailing: DiaryInkAction(
                      label: 'Remove photo ${index + 1}',
                      tooltip: 'Remove photo ${index + 1}',
                      onPressed: () => _removePhoto(index),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: DiaryInkGlyph(
                          symbol: DiaryInkSymbol.close,
                          color: palette.muted,
                          size: 18,
                        ),
                      ),
                    ),
                    caption: index == _selected
                        ? CustomPaint(
                            foregroundPainter: DiaryInkUnderline(
                              ink: palette.muted,
                            ),
                            child: TextField(
                              key: ValueKey('diary-photo-caption-$index'),
                              controller: _moments[index].caption,
                              minLines: 2,
                              maxLines: 2,
                              maxLength: 240,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) =>
                                  FocusScope.of(context).unfocus(),
                              onTapOutside: (_) =>
                                  FocusScope.of(context).unfocus(),
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: palette.ink,
                                fontStyle: FontStyle.italic,
                              ),
                              cursorColor: palette.ink,
                              decoration: InputDecoration(
                                hintText: 'Caption (optional)',
                                hintStyle: TextStyle(
                                  color: palette.muted.withValues(alpha: .45),
                                ),
                                counterText: '',
                                contentPadding: const EdgeInsets.only(
                                  bottom: 8,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          )
                        : SizedBox(height: captionHeight),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        DiaryPhotoContactSheet(
          photos: [
            for (final moment in _moments)
              (
                path: moment.path,
                bytes: moment.bytes,
                hasWords: moment.writtenAnswers.isNotEmpty,
              ),
          ],
          selected: _selected,
          controller: _rail,
          onSelect: _selectPhoto,
          onReorder: _reorderPhoto,
          onAdd: _picking ? null : _pickPhotos,
        ),
        const SizedBox(height: 12),
        Text(
          '${_selected + 1} of ${_moments.length} ${_moments.length == 1 ? 'photo' : 'photos'}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontStyle: FontStyle.italic,
            color: palette.muted,
          ),
        ),
        if (_pickerError != null) ...[
          const SizedBox(height: 16),
          _errorNotice(),
        ],
      ],
    );
  }

  Widget _errorNotice() => Semantics(
    liveRegion: true,
    child: Text(
      _pickerError!,
      style: TextStyle(color: context.colors.error, fontSize: 13, height: 1.5),
    ),
  );

  /// Whether the computer is still writing questions for this story's
  /// photos, the current one or ones waiting their turn.
  bool get _generating {
    final questions = _photoQuestions;
    if (questions == null) return false;
    final summary = ref.read(noteSummaryProvider);
    return _moments.any(
      (moment) =>
          questions.queued.contains(moment.sha) ||
          // A shuffle waits on its card, not the whole page.
          (DiaryPhotoQuestionController.asking(summary, moment.sha) &&
              !questions.shuffling.containsKey(moment.sha)),
    );
  }

  Widget _reflection() {
    _photoQuestions = ref.watch(diaryPhotoQuestionProvider);
    ref.watch(noteSummaryProvider);
    final shas = [for (final moment in _moments) moment.sha];
    if (shas.any((sha) => !_photoQuestions!.questions.containsKey(sha))) {
      // Cached questions from an earlier visit or a finished background task.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(ref.read(diaryPhotoQuestionProvider.notifier).load(shas));
        }
      });
    }
    // Add new questions from shuffle, once each, and show them.
    for (final moment in _moments) {
      final fresh = _photoQuestions!.fresh[moment.sha];
      if (fresh == null || !moment.applied.add(fresh.id)) continue;
      final g = fresh.group;
      moment.extra[g].add(fresh.question);
      final list = moment.groups(_generated(moment))[g];
      moment.variants[g] = list.indexWhere((q) => q.text == fresh.question);
    }
    return _generating ? _generatingQuestions() : _reflectionDesk();
  }

  /// Shown from **Generate questions** until the computer has finished.
  Widget _generatingQuestions() {
    final palette = DiaryMemoryPalette.of(context);
    return Semantics(
      key: const ValueKey('diary-photo-generating'),
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 64),
        child: Column(
          children: [
            SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _moments.length == 1
                  ? 'Writing questions for your photo…'
                  : 'Writing questions for your photos…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: 10),
            DiaryInkAction(
              key: const ValueKey('diary-photo-stop'),
              label: 'Stop',
              onPressed: () => unawaited(
                ref.read(diaryPhotoQuestionProvider.notifier).stop(),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Stop',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: palette.ink,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shuffle: a new question from the computer for this photo and group,
  /// or the next question already here when the computer can't help.
  Future<void> _shuffle() async {
    final moment = _moment, group = moment.group;
    void cycle() => setState(
      () => moment.variants[group] =
          (moment.variants[group] + 1) %
          moment.groups(_generated(moment))[group].length,
    );
    if (moment.draft.missing) return cycle();
    final sent = await ref
        .read(diaryPhotoQuestionProvider.notifier)
        .another(
          date: TimeHelper.dateKey(widget.date),
          photoSha: moment.sha,
          photo: moment.bytes,
          group: group,
          shown: [
            for (final q in moment.groups(_generated(moment))[group]) q.text,
          ],
          caption: moment.caption.text,
        );
    if (!sent && mounted) cycle();
  }

  /// **Generate questions**: asks the computer about every photo here.
  void _generateQuestions() {
    _shownReason = null;
    final controller = ref.read(diaryPhotoQuestionProvider.notifier);
    final asked = controller.generate(
      date: TimeHelper.dateKey(widget.date),
      photos: [
        for (final moment in _moments)
          (
            photoSha: moment.sha,
            photo: moment.bytes,
            caption: moment.caption.text,
          ),
      ],
    );
    _changeStage(_PhotoStage.reflect);
    // A refusal can arrive before Reflect starts listening.
    unawaited(
      asked.then((_) {
        if (!mounted) return;
        final messages = ref.read(diaryPhotoQuestionProvider).messages;
        final reason = _moments
            .map((moment) => messages[moment.sha])
            .nonNulls
            .firstOrNull;
        if (reason != null) _showReason(reason);
      }),
    );
  }

  Widget _reflectionDesk() {
    final generated = _generated(_moment);
    return DiaryReflectionDesk(
      photos: [
        for (final moment in _moments)
          (
            bytes: moment.bytes,
            caption: moment.caption.text.trim(),
            hasWords: moment.writtenAnswers.isNotEmpty,
          ),
      ],
      selectedPhoto: _selected,
      selectedGroup: _moment.group,
      groupLabels: [for (final group in diaryPhotoGroups) group.label],
      groupHasWords: [
        for (var g = 0; g < diaryPhotoGroups.length; g++)
          _moment.groupHasWords(g),
      ],
      question: _moment.question(generated).text,
      answer: _moment.answer(generated),
      questionAnchor: _questionAnchor,
      onSelectPhoto: _selectPhoto,
      onSelectGroup: (index) => setState(() => _moment.group = index),
      loadingQuestion: _photoQuestions?.shuffling[_moment.sha] == _moment.group,
      onAnotherQuestion: _shuffle,
      onEnlargePhoto: (index) => _showPhoto(_moments[index], index),
      onAnswerChanged: () => setState(() {}),
    );
  }

  Widget _entryPreview() => _opening
      ? Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Center(
            child: Text(
              'Opening your photo story…',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: DiaryMemoryPalette.of(context).muted,
              ),
            ),
          ),
        )
      : DiaryPhotoEntryBook(
          stories: [
            for (final moment in _moments)
              (
                bytes: moment.bytes,
                caption: moment.caption.text.trim(),
                reflections: [
                  if (_includeReflections)
                    for (final answer in moment.writtenAnswers)
                      (question: answer.key, answer: answer.value.text.trim()),
                ],
                seen: _includeReflections && moment.keepSeen
                    ? moment.seen.text.trim()
                    : '',
              ),
          ],
          onEnlarge: (index) => _showPhoto(_moments[index], index),
          onEditPhotos: widget.readOnly ? null : _editPhotos,
          onReflect: widget.readOnly
              ? null
              : (index) {
                  _selected = index;
                  _changeStage(_PhotoStage.reflect);
                },
        );

  Widget _footer() {
    if (_stage == _PhotoStage.reflect && _generating) {
      return const SizedBox.shrink();
    }
    if (_stage == _PhotoStage.reflect) {
      return DiaryReflectionControls(
        nextLabel: _moment.group < 2
            ? 'Next question'
            : (_selected < _moments.length - 1 ? 'Next photo' : 'See my entry'),
        onNext: _advance,
        onReview: () => _review(includeReflections: true),
      );
    }
    final palette = DiaryMemoryPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_stage == _PhotoStage.photos && _moments.isEmpty)
            DiaryPaperTicket(
              label: _picking ? 'Opening your photos…' : 'Choose photos',
              onPressed: _picking ? null : _pickPhotos,
              symbol: DiaryInkSymbol.album,
            ),
          if (_stage == _PhotoStage.photos && _moments.isNotEmpty)
            if (_canReturnToEntry)
              DiaryPaperTicket(
                label: 'Back to entry',
                onPressed: _picking ? null : _finishEditingPhotos,
                symbol: DiaryInkSymbol.album,
                tone: 2,
              )
            else ...[
              DiaryPaperTicket(
                label: 'Generate questions',
                onPressed: _picking ? null : _generateQuestions,
                symbol: DiaryInkSymbol.sun,
              ),
              const SizedBox(height: 6),
              DiaryInkAction(
                label: 'Just the photos',
                onPressed: _picking
                    ? null
                    : () => _review(includeReflections: false),
                child: Center(
                  child: Text(
                    'Just the photos',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: palette.muted,
                    ),
                  ),
                ),
              ),
            ],
          if (_stage == _PhotoStage.review) ...[
            Text(
              _moments.any((moment) => moment.draft.missing)
                  ? 'Some photos are kept only on the device that added them. Sync shares captions and words, not photos.'
                  : 'Photos stay on this device. Sync shares captions and words, not photos.',
              key: const ValueKey('diary-photo-local-note'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, height: 1.5, color: palette.muted),
            ),
            if (widget.readOnly) ...[
              const SizedBox(height: 4),
              Text(
                'Saved stories can be changed on your primary device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: palette.muted,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (widget.readOnly)
              DiaryPaperTicket(
                label: 'Done',
                onPressed: () => Navigator.pop(context),
                symbol: DiaryInkSymbol.check,
                tone: 2,
              )
            else
              DiaryPaperTicket(
                key: const ValueKey('diary-photo-save'),
                label: _saving
                    ? 'Saving…'
                    : _reopened
                    ? 'Save changes'
                    : 'Save to diary',
                onPressed: _saving || _opening || _moments.isEmpty
                    ? null
                    : _save,
                symbol: DiaryInkSymbol.check,
                tone: 2,
              ),
          ],
        ],
      ),
    );
  }
}
