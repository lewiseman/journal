import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai_settings.dart';
import '../core/engine_registry.dart';

class DeviceModeSelector extends ConsumerWidget {
  const DeviceModeSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    if (ref.watch(onDeviceEngineProvider) == null) {
      if (settings.mode != AiMode.device &&
          !settings.overrides.values.contains(AiMode.device)) {
        return const SizedBox.shrink();
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The device engine is unavailable. Choose Companion to continue.',
              ),
              TextButton(
                onPressed: () async {
                  final controller = ref.read(aiSettingsProvider.notifier);
                  for (final entry in settings.overrides.entries) {
                    if (entry.value == AiMode.device) {
                      await controller.setOverride(entry.key, AiMode.auto);
                    }
                  }
                  await controller.setMode(AiMode.companion);
                },
                child: const Text('Use Companion'),
              ),
            ],
          ),
        ),
      );
    }
    Future<void> choose(AiMode mode) async {
      try {
        await ref.read(aiSettingsProvider.notifier).setMode(mode);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save the AI setting.')),
          );
        }
      }
    }

    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Where AI runs', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final choices = [
              _ModeChoice(
                key: const ValueKey('ai-mode-companion'),
                title: 'Companion',
                subtitle: 'Your computer',
                icon: Icons.desktop_mac_rounded,
                selected: settings.mode == AiMode.companion,
                onTap: () => choose(AiMode.companion),
              ),
              _ModeChoice(
                key: const ValueKey('ai-mode-device'),
                title: 'On this phone',
                subtitle: 'Works offline',
                icon: Icons.phone_iphone_rounded,
                selected: settings.mode == AiMode.device,
                onTap: () => choose(AiMode.device),
              ),
            ];
            if (constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [choices[0], const SizedBox(height: 10), choices[1]],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: choices[0]),
                  const SizedBox(width: 12),
                  Expanded(child: choices[1]),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Semantics(
          selected: settings.mode == AiMode.auto,
          child: Material(
            color: settings.mode == AiMode.auto
                ? colors.primaryContainer.withValues(alpha: .5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: const ValueKey('ai-mode-auto'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => choose(AiMode.auto),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      color: colors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Auto',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            const TextSpan(
                              text: ' · Computer when connected, phone when ready.',
                            ),
                          ],
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (settings.mode == AiMode.auto) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (settings.mode == AiMode.device)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Keep Journal in the foreground while AI works.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: selected
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: .6),
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: colors.primary, size: 26),
                    const Spacer(),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: selected ? colors.primary : colors.outlineVariant,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
