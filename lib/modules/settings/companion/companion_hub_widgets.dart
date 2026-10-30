import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';

import 'companion_controller.dart';
import '../../local_ai/ui/ai_studio_material.dart';

class CompanionDetailLayout extends StatelessWidget {
  const CompanionDetailLayout({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => QvacAssistantPage(
    enabled: false,
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A short physical press gives the controls the same tactile feel as QVAC.
class CompanionSurfaceButton extends StatefulWidget {
  const CompanionSurfaceButton({
    super.key,
    required this.child,
    this.onTap,
    this.color,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  @override
  State<CompanionSurfaceButton> createState() => _CompanionSurfaceButtonState();
}

class _CompanionSurfaceButtonState extends State<CompanionSurfaceButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: _pressed ? .98 : 1,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 110),
      child: AiStudioPaper(
        color: widget.color,
        padding: const EdgeInsets.all(5),
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        child: widget.child,
      ),
    );
  }
}

class CompanionDetailHeading extends StatelessWidget {
  const CompanionDetailHeading({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: context.colors.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, size: 34, color: context.colors.primary),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(color: context.colors.onSurfaceVariant, height: 1.5),
        ),
      ],
    ),
  );
}

String companionComputerStatus(CompanionState state) => switch (state.phase) {
  CompanionPhase.connected => 'Connected',
  CompanionPhase.connecting => 'Connecting…',
  _ when state.selected?.enabled == false => 'Paused',
  _ => 'Offline',
};

class CompanionComputerCard extends StatelessWidget {
  const CompanionComputerCard({
    super.key,
    required this.state,
    required this.onTap,
  });
  final CompanionState state;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CompanionSurfaceButton(
      key: const ValueKey('companion-computers'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 60,
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.desktop_mac_rounded,
                color: colors.primary,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.selected?.name ??
                        '${state.computers.length} saved computers',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        state.phase == CompanionPhase.connected
                            ? Icons.link_rounded
                            : Icons.link_off_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          state.selected == null
                              ? 'Choose a computer'
                              : companionComputerStatus(state),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class CompanionShortcuts extends StatelessWidget {
  const CompanionShortcuts({
    super.key,
    required this.onVoice,
    required this.onHistory,
  });
  final VoidCallback onVoice, onHistory;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = [
      _Shortcut(
        key: const ValueKey('companion-reply-voice'),
        title: 'Voice',
        caption: 'Choose how I sound',
        voice: true,
        color: Color.alphaBlend(
          colors.secondaryContainer.withValues(alpha: .48),
          colors.surface,
        ),
        ink: colors.onSecondaryContainer,
        onTap: onVoice,
      ),
      _Shortcut(
        key: const ValueKey('companion-ai-task-history'),
        title: 'Past work',
        caption: 'AI task history',
        voice: false,
        color: Color.alphaBlend(
          colors.tertiaryContainer.withValues(alpha: .4),
          colors.surface,
        ),
        ink: colors.onTertiaryContainer,
        onTap: onHistory,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [items[0], const SizedBox(height: 12), items[1]],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: items[0]),
            const SizedBox(width: 12),
            Expanded(child: items[1]),
          ],
        );
      },
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    super.key,
    required this.title,
    required this.caption,
    required this.voice,
    required this.color,
    required this.ink,
    required this.onTap,
  });
  final String title, caption;
  final bool voice;
  final Color color, ink;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final captionStyle = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: ink.withValues(alpha: .8), height: 1.4);
    // Reserve two lines using the actual font and accessibility text scale.
    final captionMeasure = TextPainter(
      text: TextSpan(text: '\n', style: captionStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout();
    final captionHeight = captionMeasure.height;
    captionMeasure.dispose();
    return CompanionSurfaceButton(
      color: color,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: SizedBox(
                height: 68,
                width: 104,
                child: CustomPaint(
                  painter: _ShortcutPainter(voice, ink, context.colors.surface),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: studioTitle(context, size: 21).copyWith(color: ink),
                  ),
                ),
                Icon(Icons.arrow_outward_rounded, size: 18, color: ink),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: captionHeight,
              child: Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: captionStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutPainter extends CustomPainter {
  const _ShortcutPainter(this.voice, this.ink, this.paper);
  final bool voice;
  final Color ink, paper;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final wash = Paint()..color = ink.withValues(alpha: .07);
    canvas.drawOval(const Rect.fromLTWH(0, 10, 98, 54), wash);
    if (voice) {
      canvas.drawArc(
        const Rect.fromLTWH(12, 6, 58, 58),
        3.14,
        3.14,
        false,
        stroke,
      );
      for (final x in [12.0, 60.0]) {
        final pad = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 31, 10, 23),
          const Radius.circular(5),
        );
        canvas.drawRRect(pad, Paint()..color = paper);
        canvas.drawRRect(pad, stroke);
      }
      for (var i = 0; i < 5; i++) {
        final height = const [10.0, 19.0, 28.0, 16.0, 8.0][i];
        canvas.drawLine(
          Offset(30 + i * 6, 43 - height / 2),
          Offset(30 + i * 6, 43 + height / 2),
          stroke,
        );
      }
      canvas.drawCircle(
        const Offset(87, 20),
        3,
        Paint()..color = ink.withValues(alpha: .35),
      );
    } else {
      canvas.save();
      canvas.translate(42, 36);
      for (var i = 2; i >= 0; i--) {
        canvas.save();
        canvas.rotate((i - 1) * .12);
        final sheet = RRect.fromRectAndRadius(
          Rect.fromLTWH(-24.0 + i * 5, -27.0 + i * 3, 43, 53),
          const Radius.circular(6),
        );
        canvas.drawRRect(sheet, Paint()..color = paper);
        canvas.drawRRect(sheet, stroke);
        if (i == 0) {
          for (var line = 0; line < 3; line++) {
            canvas.drawLine(
              Offset(-14, -12.0 + line * 9),
              Offset(line == 2 ? -1 : 8, -12.0 + line * 9),
              stroke,
            );
          }
        }
        canvas.restore();
      }
      canvas.restore();
      canvas.drawCircle(
        const Offset(84, 16),
        3,
        Paint()..color = ink.withValues(alpha: .35),
      );
    }
  }

  @override
  bool shouldRepaint(_ShortcutPainter oldDelegate) =>
      voice != oldDelegate.voice ||
      ink != oldDelegate.ink ||
      paper != oldDelegate.paper;
}

class CompanionPreferenceCard extends StatelessWidget {
  const CompanionPreferenceCard({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => CompanionSurfaceButton(
    key: const ValueKey('companion-preferences'),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 28, color: context.colors.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make it yours',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  'Diary questions & search',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            color: context.colors.onSurfaceVariant,
          ),
        ],
      ),
    ),
  );
}

class CompanionReadinessStrip extends StatelessWidget {
  const CompanionReadinessStrip({super.key, required this.state});
  final CompanionState state;
  @override
  Widget build(BuildContext context) {
    final capabilities = state.status?['capabilities'] as List? ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'AI on your computer',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
            if (capabilities.length > 1)
              ExcludeSemantics(
                child: Icon(
                  Icons.swipe_rounded,
                  size: 18,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (capabilities.isEmpty)
          const Text('Model status is not available yet.')
        else
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              key: PageStorageKey(
                'companion-model-readiness-${state.selectedId}',
              ),
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 10,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final capability in capabilities)
                    SizedBox(
                      width: MediaQuery.textScalerOf(context)
                          .scale(154)
                          .clamp(0.0, constraints.maxWidth),
                      child: _ReadinessCard(
                        capability: Map<String, dynamic>.from(
                          capability as Map,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.capability});
  final Map<String, dynamic> capability;
  @override
  Widget build(BuildContext context) {
    final (name, icon) = switch (capability['id']) {
      'text' => ('Writing', Icons.edit_note_rounded),
      'vision' => ('Photos', Icons.image_outlined),
      'image' => ('Images', Icons.palette_outlined),
      'embedding' => ('Search', Icons.manage_search_rounded),
      'transcription' => ('Listening', Icons.mic_none_rounded),
      'speech' => ('Computer voice', Icons.record_voice_over_outlined),
      _ => ('${capability['id']}', Icons.auto_awesome_outlined),
    };
    final status = switch (capability['status']) {
      'ready' => 'Ready',
      'busy' => 'Working',
      'loading' => 'Loading',
      'downloading' => 'Downloading',
      'unloaded' => 'Load model',
      'unavailable' => 'Unavailable',
      'missing' || 'not-installed' => 'Needs a model',
      _ => '${capability['status']}',
    };
    final ready = capability['status'] == 'ready';
    final colors = context.colors;
    return CompanionSurfaceButton(
      key: ValueKey('companion-capability-${capability['id']}'),
      color: ready
          ? colors.primaryContainer.withValues(alpha: .45)
          : colors.surfaceContainerLow,
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          icon: Icon(icon, size: 32),
          title: Text('$name · $status'),
          content: Text(
            '${capability['reason'] ?? (ready ? 'Ready to use on your computer.' : 'Choose and load this model in Journal Companion.')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 74),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 25, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          ready
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 12,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            status,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
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
      ),
    );
  }
}
