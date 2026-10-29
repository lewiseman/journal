import 'dart:math' as math;
import 'dart:typed_data';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_memory_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';

typedef DiaryReflectionPhoto = ({
  Uint8List bytes,
  String caption,
  bool hasWords,
});

/// A quiet photo desk: prints, index tabs and a deck of writable question slips.
class DiaryReflectionDesk extends StatefulWidget {
  const DiaryReflectionDesk({
    super.key,
    required this.photos,
    required this.selectedPhoto,
    required this.selectedGroup,
    required this.groupLabels,
    required this.groupHasWords,
    required this.question,
    required this.answer,
    required this.questionAnchor,
    required this.onSelectPhoto,
    required this.onSelectGroup,
    required this.onAnotherQuestion,
    required this.onEnlargePhoto,
    required this.onAnswerChanged,
    this.loadingQuestion = false,
  });

  final List<DiaryReflectionPhoto> photos;
  final int selectedPhoto, selectedGroup;
  final List<String> groupLabels;
  final List<bool> groupHasWords;
  final String question;
  final TextEditingController answer;
  final GlobalKey questionAnchor;
  final ValueChanged<int> onSelectPhoto, onSelectGroup;
  final ValueChanged<int> onEnlargePhoto;
  final VoidCallback onAnotherQuestion, onAnswerChanged;

  /// Shuffle is waiting for a new question from the computer.
  final bool loadingQuestion;

  @override
  State<DiaryReflectionDesk> createState() => _DiaryReflectionDeskState();
}

class _DiaryReflectionDeskState extends State<DiaryReflectionDesk> {
  final _prints = ScrollController();
  double _drag = 0;

  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void didUpdateWidget(covariant DiaryReflectionDesk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPhoto != widget.selectedPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_prints.hasClients) return;
        final target = (widget.selectedPhoto * 142.0 - 55).clamp(
          0.0,
          _prints.position.maxScrollExtent,
        );
        if (_reduced) {
          _prints.jumpTo(target);
        } else {
          _prints.animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _prints.dispose();
    super.dispose();
  }

  void _drawAnother() {
    if (widget.loadingQuestion) return;
    FocusScope.of(context).unfocus();
    widget.onAnotherQuestion();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DiaryMemoryPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 174,
          child: ListView.separated(
            key: const ValueKey('diary-reflection-prints'),
            controller: _prints,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: widget.photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _photoPrint(index, palette),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'MOMENT ${widget.selectedPhoto + 1} OF ${widget.photos.length}',
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1.5,
            color: palette.muted,
          ),
        ),
        if (widget.photos[widget.selectedPhoto].caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.photos[widget.selectedPhoto].caption,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: palette.muted,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < widget.groupLabels.length; index++) ...[
              if (index > 0) const SizedBox(width: 5),
              Expanded(child: _angleTab(index, palette)),
            ],
          ],
        ),
        const SizedBox(height: 9),
        _questionSlip(palette),
      ],
    );
  }

  Widget _photoPrint(int index, DiaryMemoryPalette palette) {
    final photo = widget.photos[index];
    final selected = index == widget.selectedPhoto;
    final angle = selected ? -.035 : (index.isEven ? -.075 : .07);
    return SizedBox(
      width: 132,
      child: Center(
        child: AnimatedRotation(
          turns: angle / (math.pi * 2),
          duration: _reduced
              ? Duration.zero
              : const Duration(milliseconds: 240),
          child: AnimatedSlide(
            offset: selected ? const Offset(0, -.025) : const Offset(0, .035),
            duration: _reduced
                ? Duration.zero
                : const Duration(milliseconds: 240),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                DiaryInkAction(
                  key: ValueKey('diary-photo-thumbnail-$index'),
                  label:
                      'Photo ${index + 1} of ${widget.photos.length}${photo.hasWords ? ', has reflections' : ''}',
                  selected: selected,
                  onPressed: () => widget.onSelectPhoto(index),
                  child: CustomPaint(
                    painter: DiaryPaperStamp(
                      paper: palette.paper,
                      ink: palette.ink,
                      shadowColor: context.colors.shadow,
                      variant: index,
                      edgeScale: .25,
                    ),
                    foregroundPainter: _PrintMarkPainter(
                      ink: palette.ink,
                      selected: selected,
                      hasWords: photo.hasWords,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 114,
                            height: 92,
                            child: DiaryPhotoImage(bytes: photo.bytes),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                (index + 1).toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 17,
                                  fontStyle: FontStyle.italic,
                                  color: palette.ink,
                                ),
                              ),
                              const Spacer(),
                              const SizedBox.square(dimension: 32),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (selected) ...[
                  Positioned(
                    top: -7,
                    child: IgnorePointer(
                      child: Transform.rotate(
                        angle: -.05,
                        child: Container(
                          width: 46,
                          height: 17,
                          color: palette.tabs[0].withValues(alpha: .85),
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 1,
                    bottom: 3,
                    child: DiaryInkAction(
                      label: 'Enlarge photo ${index + 1}',
                      tooltip: 'Enlarge photo ${index + 1}',
                      onPressed: () => widget.onEnlargePhoto(index),
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: SizedBox.square(
                          dimension: 22,
                          child: CustomPaint(
                            painter: DiaryInkGlyphPainter(
                              kind: 5,
                              ink: palette.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _angleTab(int index, DiaryMemoryPalette palette) {
    final selected = index == widget.selectedGroup;
    return DiaryInkAction(
      label: widget.groupLabels[index],
      selected: selected,
      onPressed: () {
        FocusScope.of(context).unfocus();
        widget.onSelectGroup(index);
      },
      child: CustomPaint(
        painter: _IndexTabPainter(
          color: palette.tabs[index],
          ink: palette.ink,
          selected: selected,
          variant: index,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 11, 7, 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 22,
                child: CustomPaint(
                  painter: DiaryInkGlyphPainter(
                    kind: widget.groupHasWords[index] ? 4 : index,
                    ink: palette.ink.withValues(alpha: selected ? .9 : .55),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                widget.groupLabels[index],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: palette.ink.withValues(alpha: selected ? 1 : .65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionSlip(DiaryMemoryPalette palette) {
    final questionIdentity = '${widget.selectedPhoto}:${widget.question}';
    final answerStyle = TextStyle(
      color: palette.ink,
      fontSize: 16,
      height: 1.95,
    );
    final lineHeight = MediaQuery.textScalerOf(context).scale(16) * 1.95;
    return Padding(
      key: widget.questionAnchor,
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.translate(
              offset: const Offset(3, 5),
              child: Transform.rotate(
                angle: .022,
                child: CustomPaint(
                  painter: DiaryPaperStamp(
                    paper: palette.tabs[widget.selectedGroup],
                    ink: palette.ink,
                    shadowColor: context.colors.shadow,
                    edgeScale: .45,
                    variant: 1,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Transform.rotate(
              angle: -.018,
              child: CustomPaint(
                painter: DiaryPaperStamp(
                  paper: Color.alphaBlend(
                    palette.tabs[widget.selectedGroup].withValues(alpha: .3),
                    palette.paper,
                  ),
                  ink: palette.ink,
                  shadowColor: context.colors.shadow,
                  edgeScale: .45,
                  variant: 2,
                ),
              ),
            ),
          ),
          CustomPaint(
            painter: DiaryPaperStamp(
              paper: palette.paper,
              ink: palette.ink,
              shadowColor: context.colors.shadow,
              edgeScale: .5,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(25, 24, 25, 17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Room for the shuffle mark in the corner.
                  const SizedBox(height: 30),
                  GestureDetector(
                    key: const ValueKey('diary-reflection-swipe'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) => setState(
                      () =>
                          _drag = (_drag + details.delta.dx).clamp(-75.0, 75.0),
                    ),
                    onHorizontalDragEnd: (details) {
                      final draw =
                          _drag.abs() > 35 ||
                          details.velocity.pixelsPerSecond.dx.abs() > 350;
                      setState(() => _drag = 0);
                      if (draw) _drawAnother();
                    },
                    onHorizontalDragCancel: () => setState(() => _drag = 0),
                    child: Transform.translate(
                      offset: Offset(_reduced ? 0 : _drag, 0),
                      child: Transform.rotate(
                        angle: _reduced ? 0 : _drag / 1500,
                        child: AnimatedSwitcher(
                          duration: _reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 250),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(.12, .025),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: widget.loadingQuestion
                              ? Semantics(
                                  key: const ValueKey(
                                    'diary-photo-question-loading',
                                  ),
                                  liveRegion: true,
                                  label: 'Writing a new question',
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: palette.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  key: ValueKey(questionIdentity),
                                  width: double.infinity,
                                  child: Text(
                                    widget.question,
                                    key: const ValueKey('diary-photo-question'),
                                    style: TextStyle(
                                      fontSize: 23,
                                      height: 1.4,
                                      letterSpacing: -.5,
                                      fontStyle: FontStyle.italic,
                                      color: palette.ink,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  CustomPaint(
                    painter: _RuledAnswerPainter(
                      ink: palette.ink,
                      lineHeight: lineHeight,
                    ),
                    child: TextField(
                      key: ValueKey('diary-photo-answer-$questionIdentity'),
                      controller: widget.answer,
                      minLines: 3,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      style: answerStyle,
                      cursorColor: palette.ink,
                      onChanged: (_) => widget.onAnswerChanged(),
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      decoration: InputDecoration(
                        hintText: 'Your words…',
                        hintStyle: answerStyle.copyWith(
                          color: palette.muted.withValues(alpha: .5),
                          fontStyle: FontStyle.italic,
                        ),
                        contentPadding: const EdgeInsets.only(
                          top: 4,
                          bottom: 9,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            top: 10,
            end: 10,
            child: DiaryInkAction(
              key: const ValueKey('diary-photo-another-question'),
              label: 'Try another question',
              tooltip: 'Try another question',
              onPressed: widget.loadingQuestion ? null : _drawAnother,
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: SizedBox.square(
                  dimension: 22,
                  child: CustomPaint(
                    painter: DiaryInkGlyphPainter(kind: 3, ink: palette.muted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DiaryReflectionControls extends StatelessWidget {
  const DiaryReflectionControls({
    super.key,
    required this.nextLabel,
    required this.onNext,
    required this.onReview,
  });

  final String nextLabel;
  final VoidCallback onNext, onReview;

  @override
  Widget build(BuildContext context) {
    final palette = DiaryMemoryPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 7, 22, 12),
      child: Row(
        children: [
          Expanded(
            child: DiaryInkAction(
              label: 'Review',
              onPressed: onReview,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Review',
                  style: TextStyle(
                    fontSize: 11,
                    color: palette.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DiaryInkAction(
              label: nextLabel,
              onPressed: onNext,
              child: CustomPaint(
                foregroundPainter: _NextStrokePainter(
                  ink: palette.ink,
                  reverse: Directionality.of(context) == TextDirection.rtl,
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 36, 14),
                  child: Text(
                    nextLabel,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 17,
                      fontStyle: FontStyle.italic,
                      color: palette.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndexTabPainter extends CustomPainter {
  const _IndexTabPainter({
    required this.color,
    required this.ink,
    required this.selected,
    required this.variant,
  });
  final Color color, ink;
  final bool selected;
  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    final notch = variant.isEven ? 4.0 : 2.0;
    final shape = Path()
      ..moveTo(2, 3 + notch)
      ..lineTo(size.width - 3, 1)
      ..lineTo(size.width - 1, size.height - 6)
      ..lineTo(size.width * .7, size.height - 3)
      ..lineTo(size.width * .68, size.height - 5)
      ..lineTo(3, size.height - 2)
      ..close();
    if (selected) {
      canvas.drawShadow(shape, ink.withValues(alpha: .12), 3, false);
    }
    canvas.drawPath(
      shape,
      Paint()..color = selected ? color : color.withValues(alpha: .38),
    );
    if (selected) {
      final line = Path()
        ..moveTo(13, size.height - 9)
        ..quadraticBezierTo(
          size.width * .5,
          size.height - 7,
          size.width - 12,
          size.height - 10,
        );
      canvas.drawPath(
        line,
        Paint()
          ..color = ink.withValues(alpha: .65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_IndexTabPainter oldDelegate) =>
      color != oldDelegate.color ||
      ink != oldDelegate.ink ||
      selected != oldDelegate.selected ||
      variant != oldDelegate.variant;
}

class _RuledAnswerPainter extends CustomPainter {
  const _RuledAnswerPainter({required this.ink, required this.lineHeight});
  final Color ink;
  final double lineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink.withValues(alpha: .15)
      ..strokeWidth = .6
      ..style = PaintingStyle.stroke;
    for (var y = lineHeight + 1; y < size.height; y += lineHeight) {
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..quadraticBezierTo(size.width * .45, y - .7, size.width, y + .2),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(_RuledAnswerPainter oldDelegate) =>
      ink != oldDelegate.ink || lineHeight != oldDelegate.lineHeight;
}

class _PrintMarkPainter extends CustomPainter {
  const _PrintMarkPainter({
    required this.ink,
    required this.selected,
    required this.hasWords,
  });
  final Color ink;
  final bool selected, hasWords;

  @override
  void paint(Canvas canvas, Size size) {
    if (selected) {
      final pen = Paint()
        ..color = ink.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(11, size.height - 12)
          ..quadraticBezierTo(25, size.height - 10, 35, size.height - 13),
        pen,
      );
    }
    if (hasWords) {
      canvas.save();
      canvas.translate(size.width - 27, 14);
      DiaryInkGlyphPainter(kind: 4, ink: ink).paint(canvas, const Size(17, 17));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PrintMarkPainter oldDelegate) =>
      ink != oldDelegate.ink ||
      selected != oldDelegate.selected ||
      hasWords != oldDelegate.hasWords;
}

class _NextStrokePainter extends CustomPainter {
  const _NextStrokePainter({required this.ink, required this.reverse});
  final Color ink;
  final bool reverse;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (reverse) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final pen = Paint()
      ..color = ink.withValues(alpha: .8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(12, size.height - 7)
        ..quadraticBezierTo(
          size.width * .6,
          size.height - 4,
          size.width - 9,
          size.height - 9,
        ),
      pen,
    );
    final x = size.width - 22;
    final y = size.height / 2 - 2;
    canvas.drawPath(
      Path()
        ..moveTo(x - 8, y + 1)
        ..quadraticBezierTo(x + 1, y - 1, x + 11, y)
        ..moveTo(x + 5, y - 6)
        ..lineTo(x + 11, y)
        ..lineTo(x + 4, y + 7),
      pen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NextStrokePainter oldDelegate) =>
      ink != oldDelegate.ink || reverse != oldDelegate.reverse;
}
