import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'people_paper.dart';

/// Burns [child] away as [progress] runs from 0 to 1.
///
/// The flame front sweeps diagonally from the top-left corner, so the lines
/// read first burn first. [progress] is polled every frame, which keeps the
/// burn locked to the caller's clock rather than to an animation of its own.
class BurningPaper extends StatefulWidget {
  const BurningPaper({
    super.key,
    required this.progress,
    required this.child,
    this.seed = 0,
    this.inset = 0,
  });
  final double Function() progress;
  final Widget child;
  final int seed;

  /// Transparent margin around the sheet inside [child]. It is masked along
  /// with the paper, so a drop shadow there burns away too.
  final double inset;

  /// Logical-pixel position of the flame front; the shader uses the same
  /// mapping. At 0 the sheet is untouched; at 1 every pixel is consumed.
  static double front(double progress, Size size) {
    final span = size.height + size.width * .35;
    return -170 + (span + 340) * progress.clamp(0.0, 1.0);
  }

  @override
  State<BurningPaper> createState() => _BurningPaperState();
}

class _BurningPaperState extends State<BurningPaper>
    with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _program;
  late final Ticker _ticker;
  ui.FragmentShader? _mask, _overlay;
  final _particles = <_Particle>[];
  final _random = Random();
  Duration _last = Duration.zero;
  double _time = 0, _progress = 0, _spawn = 0;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _progress = widget.progress();
    _ticker = createTicker(_tick)..start();
    _program ??= ui.FragmentProgram.fromAsset('shaders/paper_burn.frag');
    _program!.then(
      (program) {
        if (!mounted) return;
        setState(() {
          _mask = program.fragmentShader();
          _overlay = program.fragmentShader();
        });
      },
      onError: (Object error, StackTrace stack) {
        // The gradient fallback keeps the effect on unsupported renderers.
        _program = null;
        assert(() {
          debugPrint('Unable to load the burn shader: $error');
          return true;
        }());
      },
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _mask?.dispose();
    _overlay?.dispose();
    super.dispose();
  }

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, .1);
    _last = elapsed;
    _time = elapsed.inMicroseconds / 1e6;
    _progress = widget.progress().clamp(0.0, 1.0);
    if (!_reduced && _size != Size.zero) _updateParticles(dt);
    setState(() {});
  }

  void _updateParticles(double dt) {
    for (final particle in _particles) {
      particle.age += dt;
      if (particle.spark) {
        particle.velocity += Offset(0, -40 * dt);
      } else {
        particle.velocity += Offset(0, 22 * dt);
      }
      particle.position += particle.velocity * dt;
      particle.spin += particle.spinRate * dt;
    }
    _particles.removeWhere((p) => p.age >= p.life);

    final front = BurningPaper.front(_progress, _size);
    final burning = front > -40 && _progress < 1;
    if (!burning) return;
    _spawn += dt * 34;
    while (_spawn >= 1 && _particles.length < 70) {
      _spawn -= 1;
      final x = _random.nextDouble() * _size.width;
      final y = front - x * .35 + (_random.nextDouble() - .6) * 50;
      if (y < -10 || y > _size.height + 10) continue;
      final spark = _random.nextDouble() < .55;
      _particles.add(
        _Particle(
          position: Offset(x, y),
          velocity: spark
              ? Offset(
                  (_random.nextDouble() - .5) * 30,
                  -40 - _random.nextDouble() * 60,
                )
              : Offset(
                  (_random.nextDouble() - .5) * 20,
                  10 + _random.nextDouble() * 25,
                ),
          life: spark
              ? .5 + _random.nextDouble() * .8
              : 1.6 + _random.nextDouble() * 1.4,
          size: spark
              ? 1.1 + _random.nextDouble() * 1.6
              : 2 + _random.nextDouble() * 3,
          spark: spark,
          phase: _random.nextDouble() * pi * 2,
          spinRate: (_random.nextDouble() - .5) * 6,
        ),
      );
    }
    if (_spawn > 1) _spawn = 1;
  }

  Shader _maskShader(Rect bounds) {
    final shader = _mask;
    if (shader == null || _reduced) {
      // A plain soft edge moving down the page.
      final edge = (_progress * 1.1 - .05).clamp(0.0, 1.0);
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Colors.transparent, Colors.white],
        stops: [(edge - .03).clamp(0.0, 1.0), (edge + .03).clamp(0.0, 1.0)],
      ).createShader(bounds);
    }
    _configure(shader, bounds.size, 0);
    return shader;
  }

  void _configure(ui.FragmentShader shader, Size size, double mode) {
    const char = PeoplePalette.charColor, scorch = PeoplePalette.scorchColor;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, (widget.seed % 97) * .37)
      ..setFloat(3, (widget.seed % 89) * .53)
      ..setFloat(4, BurningPaper.front(_progress, size))
      ..setFloat(5, _time)
      ..setFloat(6, mode)
      ..setFloat(7, char.r)
      ..setFloat(8, char.g)
      ..setFloat(9, char.b)
      ..setFloat(10, scorch.r)
      ..setFloat(11, scorch.g)
      ..setFloat(12, scorch.b)
      ..setFloat(13, widget.inset);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            _size = bounds.size;
            return _maskShader(bounds);
          },
          child: widget.child,
        ),
        if (!reduced && _overlay != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _OverlayPainter(this, _overlay!, _progress, _time),
              ),
            ),
          ),
        if (!reduced)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ParticlePainter(List.of(_particles), _time),
              ),
            ),
          ),
      ],
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.state, this.shader, this.progress, this.time);
  final _BurningPaperState state;
  final ui.FragmentShader shader;
  final double progress, time;

  @override
  void paint(Canvas canvas, Size size) {
    state._configure(shader, size, 1);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.progress != progress || old.time != time;
}

class _Particle {
  _Particle({
    required this.position,
    required this.velocity,
    required this.life,
    required this.size,
    required this.spark,
    required this.phase,
    required this.spinRate,
  });
  Offset position, velocity;
  double age = 0, spin = 0;
  final double life, size, phase, spinRate;
  final bool spark;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.particles, this.time);
  final List<_Particle> particles;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = p.age / p.life;
      if (p.spark) {
        final heat = 1 - t;
        final color = Color.lerp(
          const Color(0xFFB8321A),
          const Color(0xFFFFD27A),
          heat,
        )!.withValues(alpha: heat.clamp(0.0, 1.0));
        canvas.drawCircle(
          p.position,
          p.size * 2.6,
          Paint()
            ..color = color.withValues(alpha: color.a * .25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(p.position, p.size, Paint()..color = color);
      } else {
        // Ash flutters side to side while it drifts down.
        final sway = sin(p.age * 3.5 + p.phase) * 10;
        final alpha = (t < .15 ? t / .15 : 1 - (t - .15) / .85) * .75;
        canvas.save();
        canvas.translate(p.position.dx + sway, p.position.dy);
        canvas.rotate(p.spin);
        final s = p.size;
        canvas.drawPath(
          Path()
            ..moveTo(-s, -s * .4)
            ..lineTo(s * .3, -s * .7)
            ..lineTo(s, s * .2)
            ..lineTo(-s * .2, s * .6)
            ..close(),
          Paint()
            ..color = Color.lerp(
              const Color(0xFF2A211C),
              const Color(0xFF6E655E),
              t,
            )!.withValues(alpha: alpha.clamp(0.0, 1.0)),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}
