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
    note: 'a little room to think',
    description:
        'Your computer does the thinking. Keep both devices on the same Wi-Fi.',
    action: 'Use Companion',
    image: 'assets/images/ai_studio_computer.png',
  ),
  (
    mode: AiMode.device,
    tab: 'Phone',
    title: 'On this phone',
    note: 'take a little possibility with you',
    description: 'Download a model once. Bring writing and image tools along, even offline.',
    action: 'Use this phone',
    image: 'assets/images/ai_studio_phone.png',
  ),
  (
    mode: AiMode.auto,
    tab: 'Auto',
    title: 'A little of both',
    note: 'wherever you find yourself',
    description:
        'Your computer when connected. Prepared phone models when you’re away.',
    action: 'Use Auto',
    image: 'assets/images/ai_studio_auto.png',
  ),
];

/// A swipeable little stationery scene. Browsing never changes the AI route.
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
    _pages = PageController(initialPage: _preview, viewportFraction: .9);
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
        duration: const Duration(milliseconds: 440),
        curve: Curves.easeInOutCubic,
      );
    }
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
    return AiStudioPaper(
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
    final reduced = MediaQuery.disableAnimationsOf(context);
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final option = _options[_preview];
    final active = settings.mode == option.mode;
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 300);
    ref.listen(aiSettingsProvider.select((value) => value.mode), (_, mode) {
      _show(_options.indexWhere((option) => option.mode == mode));
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            'ON YOUR DEVICES  /  ${settings.mode == AiMode.device
                ? 'PHONE'
                : settings.mode == AiMode.auto
                ? 'AUTO'
                : 'COMPUTER'}',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.8,
              color: colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final short = MediaQuery.sizeOf(context).height < 500;
            final height = short
                ? 145.0
                : (constraints.maxWidth * .58).clamp(185.0, 260.0);
            return SizedBox(
              height: height,
              child: PageView.builder(
                key: const ValueKey('ai-mode-deck'),
                controller: _pages,
                itemCount: _options.length,
                allowImplicitScrolling: true,
                onPageChanged: (value) => setState(() => _preview = value),
                itemBuilder: (context, index) => AnimatedBuilder(
                  animation: _pages,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Image.asset(
                      _options[index].image,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  builder: (context, child) {
                    final page =
                        _pages.hasClients &&
                            _pages.position.hasContentDimensions
                        ? _pages.page!
                        : _preview.toDouble();
                    final delta = (index - page).clamp(-1.0, 1.0);
                    return Transform.translate(
                      offset: Offset(0, reduced ? 0 : delta.abs() * 16),
                      child: Transform.rotate(
                        angle: reduced ? 0 : delta * .08,
                        child: Transform.scale(
                          scale: reduced ? 1 : 1 - delta.abs() * .12,
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (!large)
          AnimatedSwitcher(
            duration: duration,
            child: Text(
              option.note,
              key: ValueKey(option.mode),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Caveat',
                fontSize: 21,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final vertical = large || constraints.maxWidth < 280;
            final tabs = [
              for (var i = 0; i < _options.length; i++)
                Semantics(
                  selected: _preview == i,
                  child: TextButton(
                    key: ValueKey('ai-mode-${_options[i].mode.name}'),
                    onPressed: () => _show(i),
                    style: TextButton.styleFrom(
                      foregroundColor: _preview == i
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _options[i].tab,
                          style: TextStyle(
                            fontWeight: _preview == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 5),
                        AnimatedContainer(
                          duration: duration,
                          width: _preview == i ? 28 : 6,
                          height: 2,
                          decoration: BoxDecoration(
                            color: _preview == i
                                ? colors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ];
            return vertical
                ? Wrap(alignment: WrapAlignment.center, children: tabs)
                : Row(children: [for (final tab in tabs) Expanded(child: tab)]);
          },
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: duration,
          layoutBuilder: (current, previous) =>
              current ?? const SizedBox.shrink(),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Column(
            key: ValueKey(option.mode),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                option.title,
                textAlign: TextAlign.center,
                style: studioTitle(context, size: 21),
              ),
              const SizedBox(height: 7),
              Text(
                option.description,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
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
                      ? colors.primary.withValues(alpha: .08)
                      : colors.primary,
                  foregroundColor: active ? colors.primary : colors.onPrimary,
                  disabledBackgroundColor: colors.primary.withValues(
                    alpha: .07,
                  ),
                  disabledForegroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
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
            ],
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
                large ? '${_preview + 1} / 3' : 'swipe to find your fit',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Caveat',
                  fontSize: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next AI option',
              onPressed: _preview == 2 ? null : () => _show(_preview + 1),
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
          ],
        ),
        if (settings.mode == AiMode.device)
          Text(
            'Keep Journal in the foreground while AI works.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(
              fontSize: 11,
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
      ],
    );
  }
}
