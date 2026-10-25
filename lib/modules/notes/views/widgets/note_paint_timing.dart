/// Reproducible, uneven batches of washes and cross-strokes. Times are fractions
/// of paint progress, independent of viewport, palette, and frame rate.
class NotePaintTiming {
  NotePaintTiming._(this.windows);

  factory NotePaintTiming.fromSeed(int seed) {
    // A separate stream leaves the existing artwork's geometry unchanged.
    var state = (seed % 2147483646 + 35771) % 2147483646 + 1;
    double next() {
      state = (state * 48271) % 2147483647;
      return state / 2147483647;
    }

    final order = [0, 1, 2, 3];
    for (var i = order.length - 1; i > 0; i--) {
      final j = (next() * (i + 1)).floor();
      final previous = order[i];
      order[i] = order[j];
      order[j] = previous;
    }
    final firstCount = next() < .5 ? 2 : 3;
    final secondBatch = .24 + next() * .08;
    final thirdBatch = .53 + next() * .09;
    final washStarts = List<double>.filled(4, 0);
    final washDurations = List<double>.filled(4, 0);
    final glazeStarts = List<double>.filled(4, 0);
    final glazeDurations = List<double>.filled(4, 0);

    for (var i = 0; i < order.length; i++) {
      final color = order[i];
      if (i < firstCount) {
        washStarts[color] = i == 0 ? 0 : .025 + next() * .05;
        washDurations[color] = .19 + next() * .08;
      } else {
        washStarts[color] = secondBatch + next() * .04;
        washDurations[color] = .25 + next() * .09;
      }

      // Batch two mixes fresh colors with cross-strokes over earlier washes.
      // Batch three revisits the remaining colors, rather than replaying them.
      if (i < firstCount - 1) {
        glazeStarts[color] = secondBatch + .025 + next() * .055;
        glazeDurations[color] = .22 + next() * .09;
      } else {
        glazeStarts[color] = thirdBatch + next() * .045;
        final requested = .21 + next() * .085;
        glazeDurations[color] = requested.clamp(0, .90 - glazeStarts[color]);
      }
    }

    return NotePaintTiming._(
      List.unmodifiable(
        List.generate(
          4,
          (i) => NotePaintWindow(
            washStart: washStarts[i],
            washDuration: washDurations[i],
            glazeStart: glazeStarts[i],
            glazeDuration: glazeDurations[i],
          ),
        ),
      ),
    );
  }

  /// The minimum duration, and the full duration for a new note.
  static const duration = Duration(seconds: 18);
  static const _wordsPerMinute = 150;
  static final _tokens = RegExp(r'\S+', unicode: true);
  static final _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// A lightweight body-text estimate; standalone Markdown markers don't count.
  static Duration durationForContent(String content) {
    final words = _tokens
        .allMatches(content)
        .where((token) => _wordCharacter.hasMatch(token[0]!))
        .length;
    final milliseconds =
        (words * Duration.millisecondsPerMinute + _wordsPerMinute - 1) ~/
        _wordsPerMinute;
    return Duration(
      milliseconds: milliseconds < duration.inMilliseconds
          ? duration.inMilliseconds
          : milliseconds,
    );
  }

  /// Maps elapsed time in [0, 1] to paint progress without slowing the entrance.
  /// Longer paintings retain the first second's pace, ease into a slower pace
  /// over the next second, and reach the finished print at [animationDuration].
  static double progressFor(double elapsed, Duration animationDuration) {
    if (elapsed <= 0) return 0;
    if (elapsed >= 1) return 1;
    if (animationDuration <= duration) return elapsed;

    final seconds =
        animationDuration.inMicroseconds / Duration.microsecondsPerSecond;
    final time = elapsed * seconds;
    final entranceVelocity = 1 / duration.inSeconds;
    if (time <= 1) return time * entranceVelocity;

    // Integrating a one-second smoothstep velocity transition consumes half
    // a second at each velocity. Solve the remaining pace to finish exactly.
    final cruiseVelocity = (1 - 1.5 * entranceVelocity) / (seconds - 1.5);
    if (time < 2) {
      final u = time - 1;
      final integratedSmoothstep = u * u * u * (1 - u / 2);
      return (time * entranceVelocity +
              (cruiseVelocity - entranceVelocity) * integratedSmoothstep)
          .clamp(0.0, 1.0);
    }
    return (1 - (seconds - time) * cruiseVelocity).clamp(0.0, 1.0);
  }

  /// One window per original color anchor, preserving the finished composition.
  final List<NotePaintWindow> windows;
}

class NotePaintWindow {
  const NotePaintWindow({
    required this.washStart,
    required this.washDuration,
    required this.glazeStart,
    required this.glazeDuration,
  });

  final double washStart;
  final double washDuration;
  final double glazeStart;
  final double glazeDuration;
}
