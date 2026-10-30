import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai_settings.dart';
import '../core/engine_registry.dart';
import 'ai_studio_material.dart';

const _options = [
  (
    mode: AiMode.companion,
    tab: 'Computer',
    title: 'Companion',
    description:
        'Your computer does the thinking. Keep both devices on the same Wi-Fi.',
    action: 'Use Companion',
    icon: Icons.computer_rounded,
  ),
  (
    mode: AiMode.device,
    tab: 'Phone',
    title: 'On this phone',
    description: 'Download a model once. Bring writing and image tools along, even offline.',
    action: 'Use this phone',
    icon: Icons.phone_iphone_rounded,
  ),
  (
    mode: AiMode.auto,
    tab: 'Auto',
    title: 'A little of both',
    description:
        'Your computer when connected. Prepared phone models when you’re away.',
    action: 'Use Auto',
    icon: Icons.swap_horiz_rounded,
  ),
];

/// Compare AI modes before explicitly choosing where tasks should run.
class DeviceModeSelector extends ConsumerStatefulWidget {
  const DeviceModeSelector({super.key, this.onSetup});
  final VoidCallback? onSetup;

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
    _pages = PageController(initialPage: _preview);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(int index) {
    if (!_pages.hasClients || index == _preview) return;
    _pages.jumpToPage(index);
  }

  Future<void> _choose(AiMode mode) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(aiSettingsProvider.notifier).setMode(mode);
      if (mounted) {
        HapticFeedback.selectionClick();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSetup?.call();
        });
      }
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

  Widget _unavailable(AiSettings settings) {
    if (settings.mode != AiMode.device &&
        !settings.overrides.values.contains(AiMode.device)) {
      return const SizedBox.shrink();
    }
    return AiStudioCard(
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
                      final controller = ref.read(aiSettingsProvider.notifier);
                      for (final entry in settings.overrides.entries) {
                        if (entry.value == AiMode.device) {
                          await controller.setOverride(entry.key, AiMode.auto);
                        }
                      }
                      if (mounted) await _choose(AiMode.companion);
                    } catch (_) {
                      if (mounted) {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    if (ref.watch(onDeviceEngineProvider) == null) {
      return _unavailable(settings);
    }
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final option = _options[_preview];
    final active = settings.mode == option.mode;
    ref.listen(aiSettingsProvider.select((value) => value.mode), (_, mode) {
      _show(_options.indexWhere((option) => option.mode == mode));
    });
    return AiStudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              'Currently using: ${settings.mode == AiMode.device
                  ? 'Phone'
                  : settings.mode == AiMode.auto
                  ? 'Auto'
                  : 'Computer'}',
              style: text.labelMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final tabs = [
                for (var i = 0; i < _options.length; i++)
                  Semantics(
                    selected: _preview == i,
                    child: TextButton(
                      key: ValueKey('ai-mode-${_options[i].mode.name}'),
                      onPressed: () => _show(i),
                      style: TextButton.styleFrom(
                        foregroundColor: _preview == i
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                        backgroundColor: _preview == i
                            ? colors.primaryContainer
                            : Colors.transparent,
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(_options[i].tab),
                    ),
                  ),
              ];
              return large || constraints.maxWidth < 280
                  ? Wrap(spacing: 4, runSpacing: 4, children: tabs)
                  : Row(
                      children: [for (final tab in tabs) Expanded(child: tab)],
                    );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: large ? 112 : 80,
            child: PageView.builder(
              key: const ValueKey('ai-mode-deck'),
              controller: _pages,
              itemCount: _options.length,
              onPageChanged: (value) => setState(() => _preview = value),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(_options[index].icon, color: colors.primary, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _options[index].title,
                        style: studioTitle(context, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            option.description,
            style: text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: ValueKey('ai-use-${option.mode.name}'),
            onPressed: _saving
                ? null
                : active
                ? widget.onSetup
                : () => _choose(option.mode),
            style: FilledButton.styleFrom(
              backgroundColor: active
                  ? colors.primaryContainer
                  : colors.primary,
              foregroundColor: active
                  ? colors.onPrimaryContainer
                  : colors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              active
                  ? widget.onSetup == null
                        ? Icons.check_rounded
                        : Icons.south_rounded
                  : Icons.arrow_forward_rounded,
              size: 18,
            ),
            label: Text(
              active
                  ? widget.onSetup == null
                        ? 'Current choice'
                        : 'View setup'
                  : option.action,
              textAlign: TextAlign.center,
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous AI option',
                onPressed: _preview == 0 ? null : () => _show(_preview - 1),
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              Expanded(
                child: Text(
                  '${_preview + 1} / ${_options.length}',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next AI option',
                onPressed: _preview == _options.length - 1
                    ? null
                    : () => _show(_preview + 1),
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ],
          ),
          if (settings.mode == AiMode.device)
            Text(
              'Keep Journal in the foreground while AI works.',
              style: text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}
