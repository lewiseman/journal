import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'companion_controller.dart';
import 'companion_guide_voice.dart';

const _artwork = 'assets/images/more_local_qvac.png';

/// A visual walkthrough. Browsing a step never changes connection or trust.
class CompanionConnectionGuide extends ConsumerStatefulWidget {
  const CompanionConnectionGuide({
    super.key,
    required this.connection,
    required this.onScan,
    required this.onReconnect,
    required this.onCancel,
  });
  final CompanionState connection;
  final VoidCallback onScan, onReconnect, onCancel;

  @override
  ConsumerState<CompanionConnectionGuide> createState() =>
      _CompanionConnectionGuideState();
}

class _CompanionConnectionGuideState
    extends ConsumerState<CompanionConnectionGuide>
    with WidgetsBindingObserver {
  int _step = 0, _bounce = 0, _speech = 0;
  bool _speaking = false;
  CompanionGuideVoice? _voice;

  bool get _connected => widget.connection.phase == CompanionPhase.connected;
  bool get _pairing => widget.connection.phase == CompanionPhase.pairing;
  bool get _remembered => widget.connection.selected != null;
  int get _scene => _connected
      ? 3
      : _pairing
      ? 2
      : _remembered
      ? 0
      : _step;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Dialogs, the scanner and pushed settings pages also pause spoken help.
    if (ModalRoute.isCurrentOf(context) == false) _stopSpeaking();
  }

  @override
  void didUpdateWidget(CompanionConnectionGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection.phase != widget.connection.phase) {
      _stopSpeaking();
      if (oldWidget.connection.phase == CompanionPhase.pairing) _step = 1;
      if (_connected && oldWidget.connection.phase == CompanionPhase.pairing) {
        _bounce++;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopSpeaking();
      if (mounted) setState(() {});
    }
  }

  void _stopSpeaking() {
    _speech++;
    _speaking = false;
    unawaited(_voice?.stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSpeaking();
    super.dispose();
  }

  String get _title {
    final phase = widget.connection.phase;
    return switch (phase) {
      CompanionPhase.loading => 'Getting ready…',
      CompanionPhase.connected => 'You’re connected!',
      CompanionPhase.pairing => 'One last check',
      CompanionPhase.connecting => 'Looking for your computer…',
      CompanionPhase.permissionDenied => 'Allow nearby connections',
      CompanionPhase.identityChanged => 'Let’s check this computer',
      CompanionPhase.revoked => 'Connect again',
      CompanionPhase.incompatible => 'Time for an update',
      CompanionPhase.unavailable => 'Let’s find your computer',
      _ when _remembered => 'Welcome back!',
      _ => 'Let’s connect your computer',
    };
  }

  String get _instruction => switch (widget.connection.phase) {
    CompanionPhase.loading => 'Loading your saved computers…',
    CompanionPhase.permissionDenied =>
      'Allow Local Network for Journal in phone Settings.',
    CompanionPhase.incompatible => 'Update both apps. Then try again.',
    CompanionPhase.identityChanged =>
      'Check this computer in Connection details below.',
    CompanionPhase.revoked =>
      'Check this computer in Connection details below.',
    _ =>
      _connected
          ? 'Your phone and computer are linked.'
          : _pairing
          ? widget.connection.verification == null
                ? 'Keep Journal Companion open on your computer.'
                : 'Same code? Tap Approve on your computer.'
          : _remembered
          ? 'Open Journal Companion. Use the same Wi-Fi.'
          : switch (_step) {
              0 => 'Same Wi-Fi. Open Journal Companion on your computer.',
              1 => 'On your computer, tap “Connect a phone”. Scan its QR.',
              _ => 'Compare the phone code. Then approve on your computer.',
            },
  };

  String get _spoken {
    final phase = widget.connection.phase;
    final help = switch (phase) {
      CompanionPhase.permissionDenied => 'On an iPhone, open Settings, find Journal and allow Local Network access. Then try again.',
      CompanionPhase.identityChanged => 'The computer’s identity could not be verified. Do not approve a computer you do not recognize. Check its identity in connection details.',
      CompanionPhase.revoked => 'This computer no longer recognizes this phone. Check connection details. You may need to forget it and scan a fresh code.',
      CompanionPhase.incompatible => 'Update Journal on your phone and Journal Companion on your computer, then try again.',
      CompanionPhase.loading =>
        'Please wait while I check your saved computers.',
      CompanionPhase.connected => 'Your phone is connected to your computer. The model status below shows which AI tools are ready.',
      CompanionPhase.pairing =>
        widget.connection.verification == null
            ? 'Wait a moment. Keep Journal Companion open on your computer.'
            : 'Look at the phone code here and on your computer. The code on this phone is ${widget.connection.verification!.split('').join(', ')}. Compare every character. Only if they match, tap Approve on your computer.',
      _ when _remembered => 'Open Journal Companion on your computer. Put your phone and computer on the same private Wi-Fi. Then tap Connect again. If that does not work, open Need help below.',
      _ => switch (_step) {
        0 => 'Let’s connect your computer. Put your phone and computer on the same private Wi-Fi. Open Journal Companion on the computer. Then tap Next on this phone.',
        1 => 'In Journal Companion on your computer, choose Connect a phone. Tap Scan QR on this phone. Point the camera at the square code on the computer. Check the computer’s identity before continuing.',
        _ => 'After scanning, check the computer’s identity. A phone code will appear here. Compare every character with the code on the computer. Only if they match, tap Approve on the computer. I will show you when you are connected.',
      },
    };
    return help;
  }

  Future<void> _listen() async {
    if (_speaking) {
      _stopSpeaking();
      setState(() {});
      return;
    }
    final generation = ++_speech;
    setState(() {
      _speaking = true;
      _bounce++;
    });
    unawaited(HapticFeedback.selectionClick());
    try {
      _voice ??= ref.read(companionGuideVoiceProvider);
      await _voice!.speak(_spoken);
    } catch (_) {
      if (mounted && generation == _speech) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Voice is unavailable. Follow the pictures, or check your phone’s speech settings.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && generation == _speech) {
        setState(() => _speaking = false);
      }
    }
  }

  void _selectStep(int step) {
    _stopSpeaking();
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _step = step;
      _bounce++;
    });
  }

  void _act(VoidCallback action) {
    _stopSpeaking();
    setState(() {});
    action();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final state = widget.connection;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final guided = !_connected && !_pairing && !_remembered;
    final awaiting =
        state.phase == CompanionPhase.loading ||
        state.phase == CompanionPhase.connecting ||
        _pairing;
    final mascot = Semantics(
      label: _speaking ? 'Stop spoken help' : 'QVAC. Listen to this step',
      button: true,
      onTap: _listen,
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('companion-guide-mascot'),
          borderRadius: BorderRadius.circular(28),
          onTap: _listen,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_bounce),
            tween: Tween(begin: 0, end: 1),
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 520),
            builder: (context, value, child) => Transform.translate(
              offset: Offset(0, -7 * math.sin(value * math.pi)),
              child: Transform.rotate(
                angle: math.sin(value * math.pi * 2) * .04,
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset(_artwork, width: 88, height: 96),
            ),
          ),
        ),
      ),
    );
    final title = Text(
      _title,
      style: theme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -.5,
      ),
    );
    final listen = TextButton.icon(
      key: const ValueKey('companion-guide-listen'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(48, 48),
      ),
      onPressed: _listen,
      icon: Icon(
        _speaking ? Icons.stop_circle_outlined : Icons.volume_up_rounded,
        size: 22,
      ),
      label: Text(_speaking ? 'Stop' : 'Listen'),
    );
    final largeText = MediaQuery.textScalerOf(context).scale(12) > 16;
    final steps = [
      for (var i = 0; i < 3; i++)
        _StepButton(
          index: i,
          selected: _scene == i,
          // A check means an actual scan, never a tutorial tap.
          done: _pairing && i < 2,
          horizontal: largeText,
          onTap: guided && !state.busy ? () => _selectStep(i) : null,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <
                MediaQuery.textScalerOf(context).scale(210) + 114) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      mascot,
                      const SizedBox(width: 14),
                      Flexible(child: listen),
                    ],
                  ),
                  const SizedBox(height: 12),
                  title,
                ],
              );
            }
            return Row(
              children: [
                mascot,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 4), listen],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: .48),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colors.primary.withValues(alpha: .12)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_connected && !_remembered)
                  largeText
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: steps,
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final step in steps) Expanded(child: step),
                          ],
                        ),
                AnimatedSwitcher(
                  duration: duration,
                  child: _DeviceScene(key: ValueKey(_scene), step: _scene),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _instruction,
                    textAlign: TextAlign.center,
                    style: theme.titleMedium?.copyWith(
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_pairing && state.verification != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    key: const ValueKey('companion-phone-code'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text('Phone code', style: theme.labelLarge),
                        const SizedBox(height: 8),
                        SelectableText(
                          RegExp(r'.{1,4}')
                              .allMatches(state.verification!)
                              .map((part) => part.group(0))
                              .join(' '),
                          semanticsLabel:
                              'Phone verification code: ${state.verification!.split('').join(' ')}',
                          textAlign: TextAlign.center,
                          style: theme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Only approve if every character matches.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (_connected)
                  _ConnectionBadge(
                    label: 'Connected · identity verified',
                    icon: Icons.verified_user_outlined,
                  )
                else if (awaiting)
                  _ConnectionBadge(
                    label: _pairing
                        ? 'Waiting for your computer'
                        : 'Checking connection…',
                    icon: Icons.hourglass_top_rounded,
                  )
                else if (_remembered)
                  FilledButton.icon(
                    key: const ValueKey('companion-reconnect'),
                    onPressed: state.busy
                        ? null
                        : () => _act(widget.onReconnect),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Connect again'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  )
                else if (_step == 0)
                  FilledButton.icon(
                    key: const ValueKey('companion-guide-next'),
                    onPressed: state.busy ? null : () => _selectStep(1),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Next'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  )
                else
                  FilledButton.icon(
                    key: const ValueKey('companion-scan'),
                    onPressed: state.busy ? null : () => _act(widget.onScan),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 26),
                    label: const Text('Scan QR'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                if (_pairing && state.busy) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _act(widget.onCancel),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel pairing'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!_connected && !awaiting) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Your devices. Your private connection.',
                  style: theme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.index,
    required this.selected,
    required this.done,
    this.horizontal = false,
    this.onTap,
  });
  final int index;
  final bool selected, done, horizontal;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = const ['Wi-Fi', 'Scan', 'Approve'][index];
    return Semantics(
      label: 'Step ${index + 1}: $label',
      selected: selected,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('companion-step-$index'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            child: Flex(
              direction: horizontal ? Axis.horizontal : Axis.vertical,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : colors.surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: selected ? colors.primary : colors.outlineVariant,
                    ),
                  ),
                  child: Icon(
                    done
                        ? Icons.check_rounded
                        : const [
                            Icons.wifi_rounded,
                            Icons.qr_code_scanner_rounded,
                            Icons.check_circle_outline_rounded,
                          ][index],
                    color: selected ? colors.onPrimary : colors.primary,
                    size: 23,
                  ),
                ),
                SizedBox(
                  height: horizontal ? 0 : 7,
                  width: horizontal ? 12 : 0,
                ),
                Flexible(
                  flex: horizontal ? 1 : 0,
                  child: Text(
                    '${index + 1}. $label',
                    textAlign: horizontal ? TextAlign.start : TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    ),
  );
}

class _DeviceScene extends StatelessWidget {
  const _DeviceScene({super.key, required this.step});
  final int step;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: const [
      'A phone and a computer sharing one Wi-Fi network.',
      'Point the phone camera at the QR on the computer screen.',
      'Compare the phone code on both devices, then approve on the computer.',
      'Phone and computer linked with a verified connection.',
    ][step],
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1.85,
        child: CustomPaint(
          painter: _DevicesPainter(step, Theme.of(context).colorScheme),
        ),
      ),
    ),
  );
}

/// Code-native diagrams stay sharp at any screen size and follow the theme.
/// The QR is an illustration, not a pairing payload.
class _DevicesPainter extends CustomPainter {
  const _DevicesPainter(this.step, this.colors);
  final int step;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320, size.height / 173);
    final ink = colors.primary;
    final paper = colors.surface;
    final wash = colors.primaryContainer;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = paper;
    void box(Rect rect, double radius, Color color, {bool outline = true}) {
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(shape, Paint()..color = color);
      if (outline) canvas.drawRRect(shape, line);
    }

    void stroke(Offset a, Offset b) => canvas.drawLine(a, b, line);
    void check(Offset center, double scale) => canvas.drawPath(
      Path()
        ..moveTo(center.dx - 6 * scale, center.dy)
        ..lineTo(center.dx - 1 * scale, center.dy + 5 * scale)
        ..lineTo(center.dx + 9 * scale, center.dy - 6 * scale),
      line,
    );
    canvas.drawOval(
      const Rect.fromLTWH(30, 146, 260, 12),
      Paint()..color = ink.withValues(alpha: .06),
    );

    // A visible dotted path joins the devices without relying on color.
    for (var x = 100.0; x < 195; x += 10) {
      canvas.drawCircle(
        Offset(x, 101),
        1.8,
        Paint()..color = ink.withValues(alpha: .35),
      );
    }
    // Computer and its stand.
    box(const Rect.fromLTWH(178, 39, 113, 82), 9, paper);
    box(const Rect.fromLTWH(185, 46, 99, 66), 4, wash, outline: false);
    stroke(const Offset(226, 122), const Offset(226, 137));
    stroke(const Offset(244, 122), const Offset(244, 137));
    box(const Rect.fromLTWH(209, 137, 52, 6), 3, paper);
    // Phone, with a camera notch and home indicator.
    box(const Rect.fromLTWH(36, 40, 58, 106), 12, paper);
    box(const Rect.fromLTWH(42, 51, 46, 81), 5, wash, outline: false);
    stroke(const Offset(58, 46), const Offset(72, 46));
    stroke(const Offset(58, 139), const Offset(72, 139));

    if (step == 0) {
      // Wi-Fi arcs above the bridge, one source for both devices.
      for (final radius in [11.0, 21.0, 31.0]) {
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(140, 76), radius: radius),
          -math.pi * .78,
          math.pi * .56,
          false,
          line,
        );
      }
      canvas.drawCircle(const Offset(140, 76), 3, Paint()..color = ink);
      for (final center in [const Offset(65, 90), const Offset(235, 80)]) {
        canvas.drawCircle(center, 12, Paint()..color = paper);
        canvas.drawCircle(center, 3, Paint()..color = ink);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 8),
          -math.pi * .8,
          math.pi * .6,
          false,
          line,
        );
      }
    } else if (step == 1) {
      // A small illustrative QR in the computer, a camera frame in the phone.
      final qr = Paint()..color = ink;
      for (var row = 0; row < 9; row++) {
        for (var col = 0; col < 9; col++) {
          final finder =
              (row < 3 && col < 3) ||
              (row < 3 && col > 5) ||
              (row > 5 && col < 3);
          if (finder || (row * 7 + col * 3) % 5 < 2) {
            canvas.drawRect(
              Rect.fromLTWH(216.5 + col * 4, 61 + row * 4, 3, 3),
              qr,
            );
          }
        }
      }
      for (final x in [49.0, 72.0]) {
        final end = x == 49 ? 1 : -1;
        stroke(Offset(x, 77), Offset(x + 9 * end, 77));
        stroke(Offset(x, 77), Offset(x, 85));
        stroke(Offset(x, 109), Offset(x + 9 * end, 109));
        stroke(Offset(x, 109), Offset(x, 101));
      }
      stroke(const Offset(53, 93), const Offset(76, 93));
      stroke(const Offset(124, 95), const Offset(150, 95));
      stroke(const Offset(143, 88), const Offset(150, 95));
      stroke(const Offset(143, 102), const Offset(150, 95));
    } else {
      for (final center in [const Offset(65, 90), const Offset(235, 80)]) {
        canvas.drawCircle(center, 16, fill);
        check(center, 1);
      }
      canvas.drawCircle(const Offset(138, 94), 19, Paint()..color = ink);
      if (step == 3) {
        final previous = line.color;
        line.color = colors.onPrimary;
        check(const Offset(137, 94), 1.1);
        line.color = previous;
        // A few quiet celebratory rays.
        for (var i = 0; i < 5; i++) {
          final angle = -math.pi + i * math.pi / 4;
          final direction = Offset(math.cos(angle), math.sin(angle));
          stroke(
            const Offset(138, 68) + direction * 24,
            const Offset(138, 68) + direction * 30,
          );
        }
      } else {
        final previous = line.color;
        line.color = colors.onPrimary;
        stroke(const Offset(134, 89), const Offset(142, 89));
        stroke(const Offset(134, 99), const Offset(142, 99));
        line.color = previous;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DevicesPainter oldDelegate) =>
      step != oldDelegate.step || colors != oldDelegate.colors;
}
