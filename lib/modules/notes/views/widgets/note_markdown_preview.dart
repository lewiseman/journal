import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// A non-interactive markdown preview that shrinks to fit short notes.
///
/// [maxLines] sets a height budget in body-text lines. Headings, block spacing,
/// images, and tables share that budget. The final visible paragraph uses native
/// text ellipsis; the markdown source is never cut.
class NoteMarkdownPreview extends StatelessWidget {
  const NoteMarkdownPreview({
    super.key,
    required this.data,
    this.maxLines = 6,
    this.styleSheet,
  }) : assert(maxLines > 0);

  final String data;
  final int maxLines;
  final MarkdownStyleSheet? styleSheet;

  @override
  Widget build(BuildContext context) {
    final styles = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .merge(styleSheet)
        .copyWith(
          textScaler:
              styleSheet?.textScaler ?? MediaQuery.textScalerOf(context),
        );

    return IgnorePointer(
      child: _PreviewViewport(
        maxLines: maxLines,
        textDirection: Directionality.of(context),
        children: [
          MarkdownBody(data: data, fitContent: false, styleSheet: styles),
          ExcludeSemantics(
            child: Text(
              '\u2026',
              style: styles.p,
              textScaler: styles.textScaler,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewViewport extends MultiChildRenderObjectWidget {
  const _PreviewViewport({
    required this.maxLines,
    required this.textDirection,
    required super.children,
  });

  final int maxLines;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPreviewViewport(maxLines, textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPreviewViewport renderObject,
  ) {
    renderObject.update(maxLines: maxLines, textDirection: textDirection);
  }
}

class _PreviewParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPreviewViewport extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PreviewParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PreviewParentData> {
  _RenderPreviewViewport(this._maxLines, this._textDirection);

  int _maxLines;
  TextDirection _textDirection;
  bool _overflows = false;
  bool _needsLineBoundary = true;
  double _contentHeight = 0;
  double _visibleHeight = 0;
  final _clipLayer = LayerHandle<ClipRectLayer>();
  final _textClipLayer = LayerHandle<ClipPathLayer>();
  _InlineEllipsis? _inlineEllipsis;

  RenderBox get _body => firstChild!;
  RenderBox get _indicator => lastChild!;

  void update({required int maxLines, required TextDirection textDirection}) {
    if (_maxLines == maxLines && _textDirection == textDirection) return;
    _maxLines = maxLines;
    _textDirection = textDirection;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PreviewParentData) {
      child.parentData = _PreviewParentData();
    }
  }

  BoxConstraints _naturalConstraints(BoxConstraints constraints) =>
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final natural = _naturalConstraints(constraints);
    final bodySize = _body.getDryLayout(natural);
    final lineHeight = _indicator.getDryLayout(natural.loosen()).height;
    return constraints.constrain(
      Size(bodySize.width, math.min(bodySize.height, lineHeight * _maxLines)),
    );
  }

  @override
  void performLayout() {
    _needsLineBoundary = true;
    _inlineEllipsis?.dispose();
    _inlineEllipsis = null;
    final natural = _naturalConstraints(constraints);
    _indicator.layout(natural.loosen(), parentUsesSize: true);
    final lineHeight = _indicator.size.height;
    _body.layout(natural, parentUsesSize: true);

    final height = math.min(constraints.maxHeight, lineHeight * _maxLines);
    _overflows = _body.size.height > height;
    size = constraints.constrain(
      Size(_body.size.width, math.min(_body.size.height, height)),
    );

    if (_overflows) {
      _contentHeight = height;
      _visibleHeight = _contentHeight;
      final indicatorData = _indicator.parentData! as _PreviewParentData;
      indicatorData.offset = Offset(
        _textDirection == TextDirection.ltr
            ? math.max(0, size.width - _indicator.size.width)
            : 0,
        math.max(0, height - lineHeight),
      );
    } else {
      _visibleHeight = _body.size.height;
      _indicator.layout(BoxConstraints.tight(Size.zero));
    }
  }

  /// Query only paragraphs crossing the cutoff, using their existing layout.
  /// No second markdown parse, TextPainter, or post-frame measurement is needed.
  double _lineBoundary(double height) {
    var boundary = height;

    void visit(RenderObject node) {
      if (node is RenderBox) {
        final transform = node.getTransformTo(_body);
        final bounds = MatrixUtils.transformRect(
          transform,
          Offset.zero & node.size,
        );
        if (bounds.top >= boundary || bounds.bottom <= boundary) return;

        if (node is RenderParagraph) {
          final position = node.getPositionForOffset(
            Offset(node.size.width / 2, boundary - bounds.top),
          );
          // Word boundaries keep emoji and other multi-code-unit glyphs whole.
          // Look on either side to handle line starts and EOF.
          for (final offset in [position.offset, position.offset - 1]) {
            if (offset < 0) continue;
            final word = node.getWordBoundary(TextPosition(offset: offset));
            final boxes = node.getBoxesForSelection(
              TextSelection(baseOffset: word.start, extentOffset: word.end),
              // MarkdownBody forces a strut height. Glyph ink can extend past
              // it, so use the line bounds rather than overlapping ink bounds.
              boxHeightStyle: ui.BoxHeightStyle.strut,
            );
            for (final box in boxes) {
              final rect = MatrixUtils.transformRect(transform, box.toRect());
              // Tolerate rounding at a boundary shared by adjacent lines.
              if (rect.top < boundary - .01 && rect.bottom > boundary + .01) {
                boundary = math.max(0, rect.top);
              }
            }
          }
          return;
        }
      }
      node.visitChildren(visit);
    }

    // Table cells can have different line heights. Recheck after moving the
    // cutoff so that a line in an earlier column cannot be partially painted.
    double previous;
    do {
      previous = boundary;
      visit(_body);
    } while (boundary < previous);
    return boundary;
  }

  _InlineEllipsis? _buildInlineEllipsis() {
    RenderParagraph? lastParagraph;
    Rect? lastBounds;
    var lastBottom = 0.0;
    var imageBottom = 0.0;

    void visit(RenderObject node) {
      if (node is RenderBox) {
        final bounds = MatrixUtils.transformRect(
          node.getTransformTo(_body),
          Offset.zero & node.size,
        );
        if (bounds.top >= _visibleHeight) return;
        final bottom = math.min(bounds.bottom, _visibleHeight);
        if (node is RenderImage) imageBottom = math.max(imageBottom, bottom);
        if (node is RenderParagraph) {
          // Images are separate widgets in MarkdownBody. Leave any custom inline
          // widgets with the original renderer rather than painting them twice.
          // Markdown text blocks have a strut; list-marker Text widgets do not.
          // Ellipsize the item content, never its bullet or number.
          if (node.childCount == 0 &&
              node.strutStyle != null &&
              bottom >= lastBottom) {
            lastParagraph = node;
            lastBounds = bounds;
            lastBottom = bottom;
          }
          return;
        }
      }
      node.visitChildren(visit);
    }

    visit(_body);
    final paragraph = lastParagraph;
    final bounds = lastBounds;
    if (paragraph == null || bounds == null || imageBottom > lastBottom) {
      return null;
    }

    final availableHeight = math.min(
      _visibleHeight - bounds.top,
      bounds.height,
    );
    final width = math.min(
      paragraph.constraints.maxWidth,
      size.width - bounds.left,
    );
    if (availableHeight <= 0 || width <= 0) return null;
    final lineHeight = paragraph.getFullHeightForCaret(
      const TextPosition(offset: 0),
    );
    if (lineHeight <= 0) return null;

    // Only the last visible paragraph needs another text layout. The limit
    // bounds the work even when that paragraph contains a very long note.
    final painter =
        TextPainter(
          text: paragraph.text,
          textAlign: paragraph.textAlign,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
          locale: paragraph.locale,
          strutStyle: paragraph.strutStyle,
          textWidthBasis: paragraph.textWidthBasis,
          textHeightBehavior: paragraph.textHeightBehavior,
          maxLines: (availableHeight / lineHeight).ceil() + 1,
        )..layout(
          minWidth: math.min(paragraph.constraints.minWidth, width),
          maxWidth: width,
        );
    var lines = painter.computeLineMetrics().length;
    // Use the paragraph's actual height: individual glyph ascent/descent can
    // extend beyond the forced line height used by the markdown renderer.
    while (painter.height > availableHeight + .01 && lines > 0) {
      lines--;
      if (lines > 0) {
        painter
          ..maxLines = lines
          ..layout(
            minWidth: math.min(paragraph.constraints.minWidth, width),
            maxWidth: width,
          );
      }
    }
    if (lines == 0) {
      painter.dispose();
      return null;
    }

    painter
      ..maxLines = lines
      ..ellipsis = '\u2026'
      ..layout(
        minWidth: math.min(paragraph.constraints.minWidth, width),
        maxWidth: width,
      );

    if (!painter.didExceedMaxLines) {
      // This paragraph fits, but a later markdown block is hidden. Append the
      // ellipsis to its styled text; native layout makes room if the line is full.
      painter
        ..text = TextSpan(
          style: paragraph.text.style,
          children: [
            paragraph.text,
            TextSpan(text: '\u2026', style: _lastTextStyle(paragraph.text)),
          ],
        )
        ..layout(
          minWidth: math.min(paragraph.constraints.minWidth, width),
          maxWidth: width,
        );
    }

    return _InlineEllipsis(
      paragraph: paragraph,
      source: paragraph.text,
      painter: painter,
      bounds: Rect.fromLTWH(bounds.left, bounds.top, width, painter.height),
    );
  }

  TextStyle? _lastTextStyle(InlineSpan span, [TextStyle? inherited]) {
    final style = inherited?.merge(span.style) ?? span.style;
    if (span case TextSpan(children: final children?)) {
      for (final child in children.reversed) {
        final result = _lastTextStyle(child, style);
        if (result != null) return result;
      }
    }
    return span is TextSpan && (span.text?.isNotEmpty ?? false) ? style : null;
  }

  void _paintInlineBackgrounds(
    PaintingContext context,
    Offset offset,
    _InlineEllipsis ellipsis,
  ) {
    final ancestors = <RenderDecoratedBox>[];
    for (
      RenderObject? node = ellipsis.paragraph.parent;
      node != null;
      node = node.parent
    ) {
      if (node is RenderDecoratedBox) ancestors.add(node);
      if (node == _body) break;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(ellipsis.bounds.shift(offset));
    // The original text rectangle is excluded from the markdown paint. Restore
    // quote/code backgrounds there before painting the ellipsized paragraph.
    for (final ancestor in ancestors.reversed) {
      final boxPainter = ancestor.decoration.createBoxPainter(markNeedsPaint);
      boxPainter.paint(
        canvas,
        offset + ancestor.localToGlobal(Offset.zero, ancestor: _body),
        ancestor.configuration.copyWith(size: ancestor.size),
      );
      boxPainter.dispose();
    }
    canvas.restore();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_overflows) {
      _clipLayer.layer = null;
      _textClipLayer.layer = null;
      context.paintChild(_body, offset);
      return;
    }

    // Descendant sizes can be read once layout has finished. Snapping at paint
    // time keeps sizing in one pass and does not schedule another frame.
    if (_needsLineBoundary || _inlineEllipsis?.isCurrent == false) {
      _visibleHeight = _lineBoundary(_contentHeight);
      _inlineEllipsis?.dispose();
      _inlineEllipsis = _buildInlineEllipsis();
      _needsLineBoundary = false;
    }
    final inlineEllipsis = _inlineEllipsis;
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTWH(0, 0, size.width, _visibleHeight),
      (context, offset) {
        if (inlineEllipsis == null) {
          _textClipLayer.layer = null;
          context.paintChild(_body, offset);
          final indicatorData = _indicator.parentData! as _PreviewParentData;
          context.paintChild(_indicator, offset + indicatorData.offset);
          return;
        }
        final viewport = Rect.fromLTWH(0, 0, size.width, _visibleHeight);
        final clip = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(viewport)
          ..addRect(inlineEllipsis.bounds.intersect(viewport));
        _textClipLayer.layer = context.pushClipPath(
          needsCompositing,
          offset,
          viewport,
          clip,
          (context, offset) => context.paintChild(_body, offset),
          clipBehavior: Clip.hardEdge,
          oldLayer: _textClipLayer.layer,
        );
        _paintInlineBackgrounds(context, offset, inlineEllipsis);
        inlineEllipsis.painter.paint(
          context.canvas,
          offset + inlineEllipsis.bounds.topLeft,
        );
      },
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      position.dy < _visibleHeight && _body.hitTest(result, position: position);

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _overflows && child == _body
      ? Rect.fromLTWH(0, 0, size.width, _visibleHeight)
      : null;

  @override
  Rect? describeSemanticsClip(RenderObject? child) =>
      describeApproximatePaintClip(child ?? _body);

  @override
  void dispose() {
    _clipLayer.layer = null;
    _textClipLayer.layer = null;
    _inlineEllipsis?.dispose();
    super.dispose();
  }
}

class _InlineEllipsis {
  _InlineEllipsis({
    required this.paragraph,
    required this.source,
    required this.painter,
    required this.bounds,
  });

  final RenderParagraph paragraph;
  final InlineSpan source;
  final TextPainter painter;
  final Rect bounds;

  bool get isCurrent =>
      identical(paragraph.text, source) &&
      paragraph.textAlign == painter.textAlign &&
      paragraph.textDirection == painter.textDirection;

  void dispose() => painter.dispose();
}
