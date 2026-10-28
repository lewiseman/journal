import 'package:flutter/material.dart';
import 'package:journal/modules/voice/controllers/mic_permission.dart';

/// A quiet card above the voice controls for anything the person must act on:
/// the microphone permission, or a paused session's note.
class VoiceBottomCard extends StatelessWidget {
  const VoiceBottomCard({
    super.key,
    required this.ink,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.onAction,
  });

  /// The microphone permission card for [status]; empty when granted.
  static Widget? microphone({
    required MicPermission permission,
    required Color ink,
  }) {
    final (title, body, action) = switch (permission.status) {
      MicStatus.denied => (
        'Microphone is off',
        'Journal needs your microphone to hear you.',
        'Allow microphone',
      ),
      MicStatus.blocked => (
        'Microphone is blocked',
        'Turn on Microphone in Settings, then come back.',
        'Open settings',
      ),
      MicStatus.unsupported => (
        'Talking needs Android for now',
        'This device cannot record for voice yet.',
        null,
      ),
      _ => (null, null, null),
    };
    if (title == null) return null;
    return VoiceBottomCard(
      key: const ValueKey('voice-mic-card'),
      ink: ink,
      icon: Icons.mic_off_rounded,
      title: title,
      body: body,
      action: action,
      onAction: action == null || permission.asking ? null : permission.request,
    );
  }

  final Color ink;
  final IconData icon;
  final String title;
  final String? body, action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (dark ? Colors.black : Colors.white).withValues(
              alpha: dark ? .28 : .62,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ink.withValues(alpha: .08)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Row(
              children: [
                Icon(icon, size: 22, color: ink.withValues(alpha: .62)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (body != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          body!,
                          style: TextStyle(
                            color: ink.withValues(alpha: .66),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: ink,
                      backgroundColor: ink.withValues(alpha: dark ? .12 : .07),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      action!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
