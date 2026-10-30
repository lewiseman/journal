import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/recall/recall_settings.dart';

import 'companion_connection_guide.dart';
import 'companion_controller.dart';
import 'companion_hub_widgets.dart';

typedef CompanionPairAction = Future<void> Function(
  BuildContext context, {
  bool paste,
  String? expectedId,
});

class CompanionDevicesPage extends ConsumerWidget {
  const CompanionDevicesPage({super.key, required this.onPair});
  final CompanionPairAction onPair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companionControllerProvider);
    final controller = ref.read(companionControllerProvider.notifier);
    final selected = state.selected;
    return CompanionDetailLayout(
      title: 'Computers',
      children: [
        if (state.phase == CompanionPhase.pairing) ...[
          CompanionConnectionGuide(
            connection: state,
            onScan: () => onPair(context),
            onReconnect: controller.reconnect,
            onCancel: controller.cancelPairing,
          ),
          const SizedBox(height: 24),
        ] else
          const CompanionDetailHeading(
            icon: Icons.devices_rounded,
            title: 'Your computers',
            description: 'Choose a computer, or connect another.',
          ),
        if (state.message != null && state.phase != CompanionPhase.pairing) ...[
          Text(state.message!),
          const SizedBox(height: 16),
        ],
        if (state.computers.isNotEmpty) ...[
          RadioGroup<String>(
            groupValue: state.selectedId,
            onChanged: (id) {
              if (!state.busy && id != null) controller.select(id);
            },
            child: Column(
              children: [
                for (final computer in state.computers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: computer.id == state.selectedId
                          ? context.colors.primaryContainer.withValues(
                              alpha: .4,
                            )
                          : context.colors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: context.colors.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: RadioListTile<String>(
                        contentPadding: const EdgeInsets.all(12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        value: computer.id,
                        enabled: !state.busy,
                        title: Text(
                          computer.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          computer.id == state.selectedId
                              ? companionComputerStatus(state)
                              : computer.enabled
                              ? 'Saved on this phone'
                              : 'Paused',
                        ),
                        secondary: Icon(
                          Icons.desktop_mac_rounded,
                          color: context.colors.primary,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (selected != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (selected.enabled)
                  TextButton.icon(
                    onPressed: state.busy ? null : controller.disconnect,
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Disconnect'),
                  ),
                OutlinedButton.icon(
                  onPressed: state.busy
                      ? null
                      : () => selected.enabled
                            ? controller.reconnect()
                            : controller.disconnect(resume: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    selected.enabled ? 'Retry connection' : 'Reconnect',
                  ),
                ),
                TextButton.icon(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              scrollable: true,
                              icon: const Icon(Icons.computer_rounded),
                              title: Text('Forget ${selected.name}?'),
                              content: const Text(
                                'You will need a new QR to connect again. This removes this phone’s trust. If reachable, the computer also removes this phone and its retained work. If offline, remove it later on the computer.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Keep'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Forget'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await controller.forget(selected.id);
                          }
                        },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Forget computer'),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ],
        FilledButton.icon(
          key: const ValueKey('companion-add-computer'),
          onPressed: state.busy ? null : () => onPair(context),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Add computer'),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              key: const ValueKey('companion-paste'),
              onPressed: state.busy ? null : () => onPair(context, paste: true),
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Use a code'),
            ),
            TextButton.icon(
              key: const ValueKey('companion-discover'),
              onPressed: state.busy || state.scanning
                  ? null
                  : controller.discover,
              icon: const Icon(Icons.radar_rounded),
              label: Text(state.scanning ? 'Looking…' : 'Find computer'),
            ),
          ],
        ),
        if (state.discovered.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Nearby computers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Nearby names are not verified. Scan the QR on your computer.',
          ),
          for (final computer in state.discovered)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.computer_rounded),
              title: Text(computer.name),
              subtitle: Text(
                computer.version == '1'
                    ? 'Scan to verify'
                    : 'Update both apps first',
              ),
              trailing: const Icon(Icons.qr_code_scanner_rounded),
              onTap: state.busy || computer.version != '1'
                  ? null
                  : () => onPair(context, expectedId: computer.id),
            ),
        ],
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Connection details'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CompanionPrivacyPage(),
            ),
          ),
        ),
      ],
    );
  }
}

class CompanionPreferencesPage extends ConsumerWidget {
  const CompanionPreferencesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CompanionDetailLayout(
    title: 'Make it yours',
    children: [
      const CompanionDetailHeading(
        icon: Icons.tune_rounded,
        title: 'A little help, your way',
        description: 'These are on. Turn off anything you don’t want.',
      ),
      Material(
        color: context.colors.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: context.colors.primary,
                size: 30,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const ValueKey('daily-questions-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Daily diary questions'),
                value: ref.watch(dailyQuestionEnabledProvider),
                onChanged: (value) =>
                    ref.read(dailyQuestionProvider.notifier).setEnabled(value),
              ),
              const Text(
                'Ask for a question on today’s diary page. Uses up to 8 entries from this week and today, sent only to your paired computer when you ask. Turning this off deletes this phone’s question history.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      Align(
        alignment: Alignment.centerLeft,
        child: Icon(
          Icons.manage_search_rounded,
          color: context.colors.primary,
          size: 32,
        ),
      ),
      const SizedBox(height: 12),
      const RecallSettings(),
    ],
  );
}

class CompanionHelpPage extends StatelessWidget {
  const CompanionHelpPage({super.key});
  @override
  Widget build(BuildContext context) => const CompanionDetailLayout(
    title: 'Connection help',
    children: [
      CompanionDetailHeading(
        icon: Icons.handshake_outlined,
        title: 'Let’s get you connected',
        description: 'A few small checks usually do it.',
      ),
      _DetailNote(
        icon: Icons.wifi_rounded,
        title: 'One Wi-Fi',
        text: 'Put both devices on the same private Wi-Fi. Guest networks, VPNs and some hotspots can block the connection.',
      ),
      _DetailNote(
        icon: Icons.laptop_mac_rounded,
        title: 'Keep the computer app open',
        text: 'Open Journal Companion on your computer, then choose “Connect a phone”.',
      ),
      _DetailNote(
        icon: Icons.qr_code_rounded,
        title: 'Make a fresh QR',
        text: 'Codes expire. Make a new one on the computer. No camera? Choose “Use a code” and paste the full code below its QR.',
      ),
      _DetailNote(
        icon: Icons.settings_outlined,
        title: 'Allow access',
        text: 'Allow Camera to scan. On iPhone, also allow Local Network for Journal in Settings. This preview needs an IPv4 network.',
      ),
      _DetailNote(
        icon: Icons.verified_user_outlined,
        title: 'Check both codes',
        text: 'Check the computer’s identity before continuing. Compare every character of the phone code on both devices, then approve on the computer.',
      ),
    ],
  );
}

class CompanionPrivacyPage extends ConsumerWidget {
  const CompanionPrivacyPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companionControllerProvider);
    return CompanionDetailLayout(
      title: 'Connection details',
      children: [
        const CompanionDetailHeading(
          icon: Icons.shield_outlined,
          title: 'Your devices. Your control.',
          description: 'AI runs on the computer you connect.',
        ),
        const _DetailNote(
          icon: Icons.router_outlined,
          title: 'A private connection',
          text: 'Your phone connects directly to your computer on the local network. After setup, the connection works without internet or Google sign-in.',
        ),
        const _DetailNote(
          icon: Icons.touch_app_outlined,
          title: 'You choose what to share',
          text: 'Setup sends no journal content. AI tools send the content they need to your paired computer when you use them. Search by meaning can index the collections you turn on.',
        ),
        const _DetailNote(
          icon: Icons.pause_circle_outline_rounded,
          title: 'Pause or forget',
          text: 'Disconnect keeps trust and accepted work. Forget removes this phone’s trust and, if reachable, removes the phone and retained work from the computer. If offline, remove the phone later on the computer.',
        ),
        const _DetailNote(
          icon: Icons.phonelink_lock_rounded,
          title: 'Remembered on this phone',
          text: 'Computer trust stays in protected storage on this phone, outside journal sync. Revoking the phone on the computer removes access and retained work.',
        ),
        if (state.selected != null) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Computer identity'),
            leading: const Icon(Icons.fingerprint_rounded),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  state.selected!.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(state.selected!.pin),
              const SizedBox(height: 16),
            ],
          ),
        ],
        if (state.phase == CompanionPhase.unavailable &&
            state.computers.isEmpty)
          OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : ref.read(companionControllerProvider.notifier).restore,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reload saved trust'),
          ),
      ],
    );
  }
}

class _DetailNote extends StatelessWidget {
  const _DetailNote({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.colors.outlineVariant.withValues(alpha: .55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.colors.primary, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
