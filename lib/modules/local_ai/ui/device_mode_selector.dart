import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai_settings.dart';
import '../core/engine_registry.dart';

const _options = [
  (
    mode: AiMode.companion,
    tab: 'Computer',
    title: 'Companion',
    description: 'Let your computer help with writing, images, voice and search. Keep both devices on the same Wi-Fi.',
    action: 'Use Companion',
    icon: Icons.desktop_mac_rounded,
  ),
  (
    mode: AiMode.device,
    tab: 'Phone',
    title: 'On this phone',
    description: 'Take writing and image tools with you. Download a model first, then use it offline.',
    action: 'Use this phone',
    icon: Icons.phone_iphone_rounded,
  ),
  (
    mode: AiMode.auto,
    tab: 'Auto',
    title: 'A little of both',
    description: 'Prefer your computer when connected. Use prepared phone models when you’re away.',
    action: 'Use Auto',
    icon: Icons.swap_horiz_rounded,
  ),
];

/// Swiping compares options; only the explicit action changes where AI runs.
class DeviceModeSelector extends ConsumerStatefulWidget {
  const DeviceModeSelector({super.key});

  @override
  ConsumerState<DeviceModeSelector> createState() => _DeviceModeSelectorState();
}

class _DeviceModeSelectorState extends ConsumerState<DeviceModeSelector> {
  late final PageController _pages;
  late int _preview;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _preview = _options.indexWhere(
      (option) => option.mode == ref.read(aiSettingsProvider).mode,
    );
    _pages = PageController(initialPage: _preview, viewportFraction: .96);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(int index) {
    if (!_pages.hasClients || index == _preview) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _choose(AiMode mode) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(aiSettingsProvider.notifier).setMode(mode);
      if (mounted) HapticFeedback.selectionClick();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the AI setting.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    ref.listen(aiSettingsProvider.select((value) => value.mode), (_, mode) {
      _show(_options.indexWhere((option) => option.mode == mode));
    });
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
                onPressed: _saving
                    ? null
                    : () async {
                        try {
                          final controller = ref.read(
                            aiSettingsProvider.notifier,
                          );
                          for (final entry in settings.overrides.entries) {
                            if (entry.value == AiMode.device) {
                              await controller.setOverride(
                                entry.key,
                                AiMode.auto,
                              );
                            }
                          }
                          await _choose(AiMode.companion);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not save the AI setting.'),
                              ),
                            );
                          }
                        }
                      },
                child: const Text('Use Companion'),
              ),
            ],
          ),
        ),
      );
    }
    final titleStyle = text.titleLarge!.copyWith(
      fontSize: 21,
      fontWeight: FontWeight.w600,
      letterSpacing: -.4,
    );
    final bodyStyle = text.bodyMedium!.copyWith(
      color: colors.onSurfaceVariant,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Where AI runs',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Compare the options, then choose what suits you.',
          style: text.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (var i = 0; i < _options.length; i++)
              ChoiceChip(
                key: ValueKey('ai-mode-${_options[i].mode.name}'),
                label: Text(_options[i].tab),
                avatar: Icon(_options[i].icon, size: 17),
                selected: _preview == i,
                showCheckmark: false,
                onSelected: (_) => _show(i),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth * .96 - 8 - 36;
            double measure(String value, TextStyle style, double width) {
              final painter = TextPainter(
                text: TextSpan(text: value, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: math.max(1, width));
              final height = painter.height;
              painter.dispose();
              return height;
            }

            // Size the deck from the actual type scale, including narrow phones.
            final height = _options
                .map((option) {
                  final heading = math.max(
                    48.0,
                    measure(option.title, titleStyle, contentWidth - 62),
                  );
                  final description = measure(
                    option.description,
                    bodyStyle,
                    contentWidth,
                  );
                  final action = math.max(
                    48.0,
                    math.max(
                          measure(
                            option.action,
                            text.labelLarge!,
                            contentWidth - 56,
                          ),
                          measure(
                            'Current choice',
                            text.labelLarge!,
                            contentWidth - 56,
                          ),
                        ) +
                        20,
                  );
                  return 36 + heading + 12 + description + 18 + action + 2;
                })
                .reduce(math.max);
            return SizedBox(
              height: height,
              child: PageView.builder(
                key: const ValueKey('ai-mode-deck'),
                controller: _pages,
                itemCount: _options.length,
                allowImplicitScrolling: true,
                onPageChanged: (index) => setState(() => _preview = index),
                itemBuilder: (context, index) {
                  final option = _options[index];
                  final selected = settings.mode == option.mode;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedContainer(
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: selected
                            ? Color.alphaBlend(
                                colors.primaryContainer.withValues(alpha: .55),
                                colors.surface,
                              )
                            : colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: selected
                              ? colors.primary.withValues(alpha: .45)
                              : colors.outlineVariant.withValues(alpha: .6),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: colors.surface.withValues(alpha: .75),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  option.icon,
                                  color: colors.primary,
                                  size: 27,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(option.title, style: titleStyle),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(option.description, style: bodyStyle),
                          const Spacer(),
                          const SizedBox(height: 18),
                          FilledButton.tonalIcon(
                            key: ValueKey('ai-use-${option.mode.name}'),
                            onPressed: selected || _saving
                                ? null
                                : () => _choose(option.mode),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              disabledBackgroundColor: colors.primary
                                  .withValues(alpha: .08),
                              disabledForegroundColor: colors.primary,
                            ),
                            icon: Icon(
                              selected
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label: Text(
                              selected ? 'Current choice' : option.action,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Swipe to compare',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            for (var i = 0; i < _options.length; i++)
              AnimatedContainer(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                width: _preview == i ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: _preview == i ? colors.primary : colors.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Previous AI option',
              onPressed: _preview == 0 ? null : () => _show(_preview - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Next AI option',
              onPressed: _preview == _options.length - 1
                  ? null
                  : () => _show(_preview + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (settings.mode == AiMode.device)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Keep Journal in the foreground while AI works.',
              style: text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}
