import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'note_paint_timing.dart';

/// Shows [image] as a cover background with a subtle [color] tint when provided.
/// Otherwise, seeded batches of paint sweep onto washi using [color], then dry
/// into a repeatable print.
class EditNotepageBg extends StatefulWidget {
  const EditNotepageBg({
    super.key,
    required this.builder,
    this.seed = 0,
    this.color,
    this.image,
    this.animationDuration = NotePaintTiming.duration,
  });

  /// Builds the foreground with the paper opacity for the current entrance.
  /// Painted backgrounds start at 60% opaque paper to keep notes readable.
  /// Image backgrounds and completed paintings use 80% opaque paper.
  /// [imageHeaderColor] includes the tint over the visible top of the image,
  /// falling back to the tinted surface while loading or on failure.
  /// It is null when no image is selected.
  final Widget Function(
    BuildContext context,
    Animation<double> paperOpacity,
    Color? imageHeaderColor,
  )
  builder;
  final int seed;
  final Color? color;
  final ImageProvider? image;

  /// Captured on mount, with an 18-second minimum. Later updates do not retime
  /// or replay the entrance, so editing can keep its original painting pace.
  final Duration animationDuration;

  @override
  State<EditNotepageBg> createState() => _EditNotepageBgState();
}

class _EditNotepageBgState extends State<EditNotepageBg>
    with SingleTickerProviderStateMixin {
  late _PigmentField _field = _PigmentField(widget.seed);
  late final AnimationController _settle;
  late final Animation<double> _paintProgress;
  late final Animation<double> _paperOpacity;
  ui.FragmentShader? _shader;
  bool _shaderRequested = false;
  bool _visible = true;
  ImageStream? _imageStream;
  late final _imageListener = ImageStreamListener(
    _onImage,
    onError: (Object error, StackTrace? stack) {
      _headerRequest++;
      _headerImage?.dispose();
      _headerImage = null;
      if (mounted) setState(() => _imageHeaderColor = null);
    },
  );
  ImageInfo? _headerImage;
  Color? _imageHeaderColor;
  int _headerRequest = 0;
  Size _backgroundSize = Size.zero;

  void _resolveHeaderImage() {
    final stream = widget.image?.resolve(
      createLocalImageConfiguration(context),
    );
    if (stream?.key == _imageStream?.key) {
      _sampleImageHeader();
      return;
    }
    _headerRequest++;
    _imageStream?.removeListener(_imageListener);
    _headerImage?.dispose();
    _headerImage = null;
    _imageHeaderColor = null;
    _imageStream = stream;
    stream?.addListener(_imageListener);
  }

  void _onImage(ImageInfo image, bool synchronousCall) {
    _headerImage?.dispose();
    _headerImage = image;
    _sampleImageHeader();
  }

  Future<void> _sampleImageHeader() async {
    final info = _headerImage;
    if (info == null) return;
    final size = _backgroundSize;
    if (size.isEmpty) return;
    final request = ++_headerRequest;
    final image = info.image.clone();
    final surface = Theme.of(context).colorScheme.surface;
    final headerHeight =
        (MediaQuery.viewPaddingOf(context).top + kToolbarHeight).clamp(
          1.0,
          size.height,
        );
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, imageSize, size);
    final source = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & imageSize,
    );
    // Match Image's centered cover crop, then inspect only the exposed header.
    final header = Rect.fromLTWH(
      source.left,
      source.top,
      source.width,
      source.height * headerHeight / size.height,
    );
    ui.Image? sample;
    ui.Picture? picture;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const target = Rect.fromLTWH(0, 0, 32, 8);
      canvas.drawColor(surface, BlendMode.src);
      canvas.drawImageRect(
        image,
        header,
        target,
        Paint()..filterQuality = FilterQuality.low,
      );
      picture = recorder.endRecording();
      sample = await picture.toImage(32, 8);
      final pixels = await sample.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (pixels == null || !mounted || request != _headerRequest) return;
      var red = 0;
      var green = 0;
      var blue = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        red += pixels.getUint8(i);
        green += pixels.getUint8(i + 1);
        blue += pixels.getUint8(i + 2);
      }
      final count = pixels.lengthInBytes ~/ 4;
      final color = Color.fromARGB(
        255,
        red ~/ count,
        green ~/ count,
        blue ~/ count,
      );
      if (color != _imageHeaderColor) setState(() => _imageHeaderColor = color);
    } catch (_) {
      // Keep the theme fallback if this renderer cannot read image pixels.
    } finally {
      sample?.dispose();
      picture?.dispose();
      image.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    final duration = widget.animationDuration < NotePaintTiming.duration
        ? NotePaintTiming.duration
        : widget.animationDuration;
    _settle = AnimationController(
      vsync: this,
      duration: duration,
      // Keep the full entrance duration regardless of system motion settings.
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onSettleStatus);
    _paintProgress = _settle.drive(
      CurveTween(curve: _ReadingPaceCurve(duration)),
    );
    // Keep notes readable from the start while leaving the backdrop visible.
    _paperOpacity = _paintProgress
        .drive(
          CurveTween(curve: const Interval(.9, 1, curve: Curves.easeInOut)),
        )
        .drive(Tween<double>(begin: .65, end: .78));
    _loadShaders();
  }

  void _loadShaders() {
    if (widget.image != null || _shaderRequested) return;
    _shaderRequested = true;
    ui.FragmentProgram.fromAsset('shaders/wabi_sabi.frag').then(
      (program) {
        if (!mounted) return;
        setState(() {
          _shader = program.fragmentShader();
        });
        _startSettle();
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted) return;
        _settle.value = 1;
        // Canvas pigment washes remain available on unsupported renderers.
        assert(() {
          debugPrint('Unable to load the pigment shader: $error');
          return true;
        }());
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveHeaderImage();
    _visible = TickerMode.valuesOf(context).enabled;
    // A covered route settles immediately and does not replay on return.
    // Initial offstage layout must not consume an entrance that hasn't begun.
    if (!_visible && _settle.isAnimating) {
      _settle.value = 1;
    }
    _startSettle();
  }

  @override
  void didUpdateWidget(covariant EditNotepageBg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolveHeaderImage();
    if (oldWidget.seed != widget.seed) _field = _PigmentField(widget.seed);
    if (widget.image != null && _settle.isAnimating) {
      _settle.value = 1;
    }
    _loadShaders();
    _startSettle();
  }

  void _startSettle() {
    if (widget.image == null &&
        _visible &&
        _settle.isDismissed &&
        _shader != null) {
      _settle.forward();
    }
  }

  void _onSettleStatus(AnimationStatus status) {
    // Restore raster caching for the backdrop once painting has finished.
    if (status == AnimationStatus.completed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _headerRequest++;
    _imageStream?.removeListener(_imageListener);
    _headerImage?.dispose();
    _settle.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (size != _backgroundSize) {
        _backgroundSize = size;
        _sampleImageHeader();
      }
      return _buildBackground(context);
    },
  );

  Widget _buildBackground(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final imageTint = (widget.color ?? colors.surface).withValues(alpha: .4);
    final child = widget.builder(
      context,
      widget.image == null
          ? _paperOpacity
          : const AlwaysStoppedAnimation<double>(.8),
      widget.image == null
          ? null
          : Color.alphaBlend(imageTint, _imageHeaderColor ?? colors.surface),
    );
    if (widget.image != null) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(imageTint, BlendMode.srcOver),
                    child: ColoredBox(
                      color: colors.surface,
                      child: Image(
                        image: widget.image!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      );
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  willChange: !_settle.isCompleted,
                  painter: _WabiSabiPainter(
                    field: _field,
                    pigment: widget.color ?? colors.primary,
                    surface: colors.surface,
                    dark: colors.brightness == Brightness.dark,
                    shader: _shader,
                    settle: _paintProgress,
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ReadingPaceCurve extends Curve {
  const _ReadingPaceCurve(this.duration);

  final Duration duration;

  @override
  double transformInternal(double t) =>
      NotePaintTiming.progressFor(t, duration);
}

/// Park–Miller arithmetic stays exact on both the Dart VM and JavaScript.
/// It also keeps compositions stable across changes to Dart's Random class.
class _PrintRandom {
  _PrintRandom(int seed) : _state = seed % 2147483646 + 1;

  int _state;

  double next() {
    _state = (_state * 48271) % 2147483647;
    return _state / 2147483647;
  }
}

/// Only four anchors are needed; the shader grows their texture per pixel.
/// Resizing returns to the seed instead of advancing a shared random stream.
class _PigmentField {
  _PigmentField(this.seed) : timing = NotePaintTiming.fromSeed(seed);

  final int seed;
  final NotePaintTiming timing;
  Size? _size;
  List<_PigmentBloom> blooms = [];

  void layout(Size size) {
    if (size == _size) return;
    _size = size;
    final random = _PrintRandom(seed);
    final unit = size.shortestSide;
    final mirror = random.next() > .5;
    Offset point(double x, double y) =>
        Offset(size.width * (mirror ? 1 - x : x), size.height * y);

    blooms = [
      _PigmentBloom(
        point(.02, .035 + random.next() * .04),
        unit * (.76 + random.next() * .12),
      ),
      _PigmentBloom(point(.92, -.055), unit * (.58 + random.next() * .12)),
      _PigmentBloom(
        point(1.04, .99 + random.next() * .025),
        unit * (.84 + random.next() * .14),
      ),
      _PigmentBloom(point(.05, 1.075), unit * (.64 + random.next() * .1)),
    ];
  }
}

class _PigmentBloom {
  const _PigmentBloom(this.center, this.radius);

  final Offset center;
  final double radius;
}

class _GlazePalette {
  _GlazePalette(Color source, Color surface, bool dark) {
    final hsl = HSLColor.fromColor(source);
    final saturation = (hsl.saturation * .7 + .1).clamp(.12, .65);
    Color tone(double shift, double saturation, double lightness) =>
        HSLColor.fromAHSL(
          1,
          (hsl.hue + shift) % 360,
          saturation,
          lightness,
        ).toColor();
    paper = Color.lerp(
      surface,
      dark ? const Color(0xff242320) : const Color(0xfff5efe3),
      .6,
    )!;
    final clay = Color.lerp(
      tone(190, saturation * .7, dark ? .57 : .52),
      const Color(0xffbd8266),
      .38,
    )!;
    colors = [
      tone(0, saturation, dark ? .56 : .42),
      clay,
      tone(-32, saturation * .65, dark ? .51 : .48),
      Color.lerp(tone(30, saturation, .55), const Color(0xffc9a36a), .68)!,
    ];
  }

  late final Color paper;
  late final List<Color> colors;
}

class _WabiSabiPainter extends CustomPainter {
  const _WabiSabiPainter({
    required this.field,
    required this.pigment,
    required this.surface,
    required this.dark,
    required this.settle,
    this.shader,
  }) : super(repaint: settle);

  final _PigmentField field;
  final Color pigment;
  final Color surface;
  final bool dark;
  final Animation<double> settle;
  final ui.FragmentShader? shader;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    field.layout(size);
    final bounds = Offset.zero & size;
    final palette = _GlazePalette(pigment, surface, dark);
    if (shader != null) {
      final random = _PrintRandom(field.seed + 72317);
      // Progress is bounded: one reveal, ending on the original static print.
      final uniforms = <double>[
        size.width,
        size.height,
        random.next() * 64,
        random.next() * 64,
        dark ? 1 : 0,
        palette.paper.r,
        palette.paper.g,
        palette.paper.b,
        for (final color in palette.colors) ...[color.r, color.g, color.b],
        for (final bloom in field.blooms) ...[
          bloom.center.dx,
          bloom.center.dy,
          bloom.radius,
        ],
        settle.value,
        for (final window in field.timing.windows) ...[
          window.washStart,
          window.washDuration,
          window.glazeStart,
          window.glazeDuration,
        ],
      ];
      for (var i = 0; i < uniforms.length; i++) {
        shader!.setFloat(i, uniforms[i]);
      }
      canvas.drawRect(bounds, Paint()..shader = shader);
      return;
    }
    // A light Canvas wash covers shader startup and unsupported renderers.
    canvas.drawColor(palette.paper, BlendMode.srcOver);
    if (!settle.isCompleted) return;
    for (var i = 0; i < field.blooms.length; i++) {
      final bloom = field.blooms[i];
      final color = palette.colors[i];
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = ui.Gradient.radial(bloom.center, bloom.radius, [
            color.withValues(alpha: .25),
            color.withValues(alpha: 0),
          ]),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WabiSabiPainter oldDelegate) =>
      field != oldDelegate.field ||
      pigment != oldDelegate.pigment ||
      surface != oldDelegate.surface ||
      shader != oldDelegate.shader ||
      settle != oldDelegate.settle ||
      dark != oldDelegate.dark;
}
