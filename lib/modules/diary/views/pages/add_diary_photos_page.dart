import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_memory_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_contact_sheet.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_entry_book.dart';
import 'package:journal/modules/diary/views/widgets/diary_reflection_desk.dart';

enum _PhotoStage { photos, reflect, review }

// These are deliberately sample prompts. No image analysis or AI call is made.
const _questionGroups = [
  (
    label: 'The moment',
    questions: [
      'What made you want to capture this moment?',
      'What was happening just before you took this photo?',
      'What happened after you put the camera away?',
    ],
  ),
  (
    label: 'The feeling',
    questions: [
      'What were you feeling that the photo doesn’t show?',
      'How did this moment change the rhythm of your day?',
      'If you could step back into this moment, how would it feel?',
    ],
  ),
  (
    label: 'The little things',
    questions: [
      'What’s one thing outside the frame you want to remember?',
      'What could you hear, smell, or taste in this moment?',
      'Who or what made this moment feel like yours?',
    ],
  ),
];

class _PhotoMoment {
  _PhotoMoment({required this.path, required this.bytes, required int seed})
    : variants = [seed % 3, seed % 3, seed % 3];

  final String path;
  final Uint8List bytes;
  final caption = TextEditingController();
  final answers = <String, TextEditingController>{};
  final List<int> variants;
  int group = 0;

  String get question => _questionGroups[group].questions[variants[group]];
  TextEditingController get answer =>
      answers.putIfAbsent(question, TextEditingController.new);
  Iterable<MapEntry<String, TextEditingController>> get writtenAnswers =>
      answers.entries.where((entry) => entry.value.text.trim().isNotEmpty);

  void dispose() {
    caption.dispose();
    for (final answer in answers.values) {
      answer.dispose();
    }
  }
}

/// A UI-only photo-story draft. Closing this route never writes to the diary.
class AddDiaryPhotosPage extends StatefulWidget {
  const AddDiaryPhotosPage({super.key, required this.date, this.imagePicker});

  final DateTime date;
  final Future<List<XFile>> Function()? imagePicker;

  @override
  State<AddDiaryPhotosPage> createState() => _AddDiaryPhotosPageState();
}

class _AddDiaryPhotosPageState extends State<AddDiaryPhotosPage> {
  final _moments = <_PhotoMoment>[];
  final _pages = PageController(keepPage: false);
  final _rail = ScrollController();
  final _scroll = ScrollController();
  final _questionAnchor = GlobalKey();
  _PhotoStage _stage = _PhotoStage.photos;
  _PhotoStage _reviewFrom = _PhotoStage.photos;
  int _selected = 0;
  bool _picking = false;
  bool _includeReflections = true;
  bool _editingPhotos = false;
  bool get _canReturnToEntry => _editingPhotos && _moments.isNotEmpty;
  String? _pickerError;

  _PhotoMoment get _moment => _moments[_selected];
  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pickPhotos();
    });
  }

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
      final added = <_PhotoMoment>[];
      var unreadable = 0;
      for (final file in files) {
        if (!paths.add(file.path)) continue;
        try {
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) throw const FormatException('Empty photo');
          added.add(
            _PhotoMoment(
              path: file.path,
              bytes: bytes,
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
    if (_moment.group < _questionGroups.length - 1) {
      setState(() => _moment.group++);
    } else if (_selected < _moments.length - 1) {
      _selectPhoto(_selected + 1);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else {
      _review(includeReflections: true);
    }
  }

  void _back() {
    if (_stage == _PhotoStage.photos && _canReturnToEntry) {
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

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final background = DiaryMemoryPalette.of(context).desk;
    return PopScope(
      canPop: _stage == _PhotoStage.photos && !_canReturnToEntry,
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
            label: _stage == _PhotoStage.photos && !_canReturnToEntry
                ? 'Close photo preview'
                : 'Back',
            tooltip: _stage == _PhotoStage.photos
                ? (_canReturnToEntry ? 'Back to entry' : 'Close photo preview')
                : (_stage == _PhotoStage.review &&
                      _reviewFrom == _PhotoStage.reflect)
                ? 'Back to reflections'
                : 'Back to photos',
            onPressed: _stage == _PhotoStage.photos && !_canReturnToEntry
                ? () => Navigator.pop(context)
                : _back,
            child: Center(
              child: Transform.flip(
                flipX: Directionality.of(context) == TextDirection.ltr,
                child: DiaryInkGlyph(
                  symbol: _stage == _PhotoStage.photos && !_canReturnToEntry
                      ? DiaryInkSymbol.close
                      : DiaryInkSymbol.arrow,
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

  void _selectSection(_PhotoStage stage) {
    if (_picking || stage == _stage) return;
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
              onPressed:
                  _picking || (_moments.isEmpty && stage != _PhotoStage.photos)
                  ? null
                  : () => _selectSection(stage),
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

  Widget _reflection() => DiaryReflectionDesk(
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
    groupLabels: [for (final group in _questionGroups) group.label],
    groupHasWords: [
      for (final group in _questionGroups)
        _moment.writtenAnswers.any(
          (answer) => group.questions.contains(answer.key),
        ),
    ],
    question: _moment.question,
    answer: _moment.answer,
    questionAnchor: _questionAnchor,
    onSelectPhoto: _selectPhoto,
    onSelectGroup: (index) => setState(() => _moment.group = index),
    onAnotherQuestion: () => setState(
      () => _moment.variants[_moment.group] =
          (_moment.variants[_moment.group] + 1) % 3,
    ),
    onEnlargePhoto: (index) => _showPhoto(_moments[index], index),
    onAnswerChanged: () => setState(() {}),
  );

  Widget _entryPreview() => DiaryPhotoEntryBook(
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
        ),
    ],
    onEnlarge: (index) => _showPhoto(_moments[index], index),
    onEditPhotos: _editPhotos,
    onReflect: (index) {
      _selected = index;
      _changeStage(_PhotoStage.reflect);
    },
  );

  Widget _footer() {
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
                onPressed: _picking
                    ? null
                    : () => _changeStage(_PhotoStage.reflect),
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
              'Preview only · photos and words aren’t saved yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, height: 1.5, color: palette.muted),
            ),
            const SizedBox(height: 12),
            DiaryPaperTicket(
              label: 'Done',
              onPressed: () => Navigator.pop(context),
              symbol: DiaryInkSymbol.check,
              tone: 2,
            ),
          ],
        ],
      ),
    );
  }
}
