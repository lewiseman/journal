import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:journal/modules/voice/views/widgets/voice_ambient_background.dart';

/// Ink and paper for the voice pages, matched to the ambient background.
class VoiceColors {
  const VoiceColors._(this.dark);
  factory VoiceColors.of(BuildContext context) =>
      VoiceColors._(Theme.of(context).brightness == Brightness.dark);
  final bool dark;
  Color get ink => dark ? const Color(0xFFF5EEF5) : const Color(0xFF302A32);
  Color get paper => dark ? const Color(0xFF241F27) : const Color(0xFFFFF9EE);
}

/// The full-screen voice layout: ambient colour behind a close header, a
/// status in the open space, the transcript settling at the bottom, then any
/// card and the controls.
class VoiceSessionScaffold extends StatelessWidget {
  const VoiceSessionScaffold({
    super.key,
    required this.background,
    required this.header,
    required this.status,
    required this.transcript,
    required this.controls,
    this.card,
  });

  final VoiceAmbientBackground background;
  final Widget header, status, transcript, controls;
  final Widget? card;

  @override
  Widget build(BuildContext context) {
    final colors = VoiceColors.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (colors.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              ),
      child: Scaffold(
        backgroundColor: colors.paper,
        body: Stack(
          children: [
            Positioned.fill(child: background),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    children: [
                      header,
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact =
                                constraints.maxHeight < 300 ||
                                MediaQuery.textScalerOf(context).scale(1) > 1.4;
                            final statusHeight = compact
                                ? (constraints.maxHeight * .18).clamp(
                                    28.0,
                                    56.0,
                                  )
                                : (constraints.maxHeight * .43).clamp(
                                    28.0,
                                    260.0,
                                  );
                            return Column(
                              children: [
                                SizedBox(
                                  height: statusHeight,
                                  child: Center(child: status),
                                ),
                                Expanded(child: transcript),
                              ],
                            );
                          },
                        ),
                      ),
                      AnimatedSize(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: card ?? const SizedBox(width: double.infinity),
                      ),
                      controls,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceSessionHeader extends StatelessWidget {
  const VoiceSessionHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.subtitle,
    this.closeTooltip = 'Close',
    this.trailing,
  });

  final String title, closeTooltip;
  final String? subtitle;
  final VoidCallback onClose;

  /// A 48px action in the right slot, such as mute or discard.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ink = VoiceColors.of(context).ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          IconButton(
            tooltip: closeTooltip,
            onPressed: onClose,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: ink,
            ),
            icon: const Icon(Icons.close_rounded, size: 23),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ink.withValues(alpha: .58),
                      fontSize: 11,
                      letterSpacing: .2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconTheme.merge(
            data: IconThemeData(color: ink),
            child: SizedBox(width: 48, child: trailing),
          ),
        ],
      ),
    );
  }
}

class VoiceSessionStatus extends StatelessWidget {
  const VoiceSessionStatus({
    super.key,
    required this.label,
    required this.icon,
  });
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ink = VoiceColors.of(context).ink;
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: ink.withValues(alpha: .60),
        fontSize: 12,
        letterSpacing: .4,
      ),
    );
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxHeight < 80
              ? Center(child: text)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 26, color: ink.withValues(alpha: .50)),
                    const SizedBox(height: 10),
                    text,
                  ],
                ),
        ),
      ),
    );
  }
}

/// A round tonal action beside one wide primary button.
class VoiceSessionControls extends StatelessWidget {
  const VoiceSessionControls({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.actionIcon,
    this.actionLabel,
    this.onAction,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final IconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = VoiceColors.of(context);
    final ink = colors.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
      child: Row(
        children: [
          if (actionIcon != null) ...[
            IconButton.filledTonal(
              tooltip: actionLabel,
              onPressed: onAction,
              style: IconButton.styleFrom(
                minimumSize: const Size(64, 64),
                foregroundColor: ink,
                backgroundColor: ink.withValues(alpha: colors.dark ? .12 : .07),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: Icon(actionIcon, size: 26),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: ink,
                foregroundColor: colors.paper,
                minimumSize: const Size(0, 64),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                elevation: 0,
              ),
              child: Text(
                primaryLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
