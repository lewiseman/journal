import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'friend_avatar.dart';
import 'people_paper.dart';

/// An unopened note drawn as a sealed envelope. Tapping cracks the wax seal
/// and lifts the flap, then calls [onOpen], which starts the reading time.
class SealedEnvelope extends StatefulWidget {
  const SealedEnvelope({
    super.key,
    required this.friendKey,
    required this.name,
    required this.seconds,
    required this.onOpen,
    this.tilt = 0,
    this.width = 210,
  });
  final String friendKey, name;
  final int seconds;
  final VoidCallback onOpen;
  final double tilt, width;

  @override
  State<SealedEnvelope> createState() => _SealedEnvelopeState();
}

class _SealedEnvelopeState extends State<SealedEnvelope>
    with SingleTickerProviderStateMixin {
  late final _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _opening = false;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (_opening) return;
    _opening = true;
    HapticFeedback.selectionClick();
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _open.forward(from: 0);
    }
    if (!mounted) return;
    widget.onOpen();
    _open.value = 0;
    _opening = false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    final height = widget.width * .62;
    return Semantics(
      button: true,
      label:
          'A note from ${widget.name}. ${widget.seconds} seconds to read, opens once.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _tap,
        child: AnimatedBuilder(
          animation: _open,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_open.value);
            return Transform.rotate(
              angle: widget.tilt * (1 - t),
              child: Transform.scale(
                scale: 1 + t * .04,
                child: SizedBox(
                  width: widget.width,
                  height: height,
                  child: CustomPaint(
                    painter: _EnvelopePainter(
                      paper: palette.paper,
                      flap: Color.lerp(palette.paper, palette.clay, .14)!,
                      edge: palette.ink.withValues(alpha: .12),
                      lift: t,
                      dark: Theme.of(context).brightness == Brightness.dark,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 12,
                          child: Row(
                            children: [
                              FriendAvatar(
                                friendKey: widget.friendKey,
                                name: widget.name,
                                size: 30,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'From ${widget.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: peopleTitle(context, size: 22),
                                    ),
                                    Row(
                                      children: [
                                        const FlameIcon(size: 11),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            '${widget.seconds}s · opens once',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: palette.muted,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: widget.width / 2 - 17,
                          top: height * .44 - 17,
                          child: Opacity(
                            opacity: (1 - t * 1.4).clamp(0, 1),
                            child: CustomPaint(
                              size: const Size.square(34),
                              painter: WaxSealPainter(palette.wax, crack: t),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  const _EnvelopePainter({
    required this.paper,
    required this.flap,
    required this.edge,
    required this.lift,
    required this.dark,
  });
  final Color paper, flap, edge;
  final double lift;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(
      body.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .35 : .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(body, Paint()..color = paper);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = edge;
    canvas.drawRRect(body, stroke);

    // Side folds meeting the lower edge.
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(size.width * .5, size.height * .5)
        ..lineTo(size.width, size.height),
      stroke,
    );

    // The flap folds back towards the viewer as it opens.
    final tip = size.height * .5 * (1 - 2 * lift);
    final flapPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * .5, tip)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(
      flapPath,
      Paint()..color = lift > .5 ? Color.lerp(flap, paper, .4)! : flap,
    );
    canvas.drawPath(flapPath, stroke);

    // A paper corner peeks out once the flap is up.
    if (lift > .4) {
      final peek = (lift - .4) / .6;
      canvas.drawRect(
        Rect.fromLTWH(
          size.width * .16,
          -size.height * .18 * peek,
          size.width * .68,
          size.height * .2 * peek,
        ),
        Paint()..color = Color.lerp(paper, Colors.white, .5)!,
      );
    }
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) =>
      old.lift != lift ||
      old.paper != paper ||
      old.flap != flap ||
      old.edge != edge ||
      old.dark != dark;
}

/// A loose, overlapping row of envelopes like letters left on a table.
class EnvelopeStack extends StatelessWidget {
  const EnvelopeStack({super.key, required this.children});
  final List<Widget> children;

  static double tiltFor(int index) =>
      (index.isEven ? -1 : 1) * (.02 + (index % 3) * .012);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 170,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 18),
      itemCount: children.length,
      separatorBuilder: (_, _) =>
          SizedBox(width: max(8, 14 - children.length * 1.0)),
      itemBuilder: (_, index) => children[index],
    ),
  );
}
