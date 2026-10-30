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

/// A simple tappable card for navigation within Local AI settings.
class CompanionSurfaceButton extends StatelessWidget {
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
  Widget build(BuildContext context) => AiStudioCard(
    color: color,
    padding: EdgeInsets.zero,
    onTap: onTap,
    child: child,
  );
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
    required this.onPreferences,
  });
  final VoidCallback onVoice, onPreferences;
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
        key: const ValueKey('companion-preferences'),
        title: 'Make it yours',
        caption: 'Diary questions & search',
        voice: false,
        color: Color.alphaBlend(
          colors.tertiaryContainer.withValues(alpha: .4),
          colors.surface,
        ),
        ink: colors.onTertiaryContainer,
        onTap: onPreferences,
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
    final text = Theme.of(context).textTheme;
    return CompanionSurfaceButton(
      color: color,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  voice ? Icons.headphones_rounded : Icons.tune_rounded,
                  size: 28,
                  color: ink,
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 20, color: ink),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: text.titleMedium?.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              caption,
              style: text.bodySmall?.copyWith(color: ink, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
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
        Text(
          'AI on your computer',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (capabilities.isEmpty)
          const Text('Model status is not available yet.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final capability in capabilities)
                _ReadinessChip(
                  capability: Map<String, dynamic>.from(capability as Map),
                ),
            ],
          ),
      ],
    );
  }
}

class _ReadinessChip extends StatelessWidget {
  const _ReadinessChip({required this.capability});
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
    return ActionChip(
      key: ValueKey('companion-capability-${capability['id']}'),
      avatar: Icon(
        icon,
        size: 17,
        color: ready ? colors.primary : colors.onSurfaceVariant,
      ),
      label: Text('$name · $status'),
      labelStyle: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: ready ? colors.primary : colors.onSurfaceVariant),
      shape: const StadiumBorder(),
      side: BorderSide(color: colors.outlineVariant.withValues(alpha: .65)),
      backgroundColor: ready
          ? colors.primaryContainer.withValues(alpha: .45)
          : colors.surfaceContainerLow,
      onPressed: () => showDialog<void>(
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
    );
  }
}
