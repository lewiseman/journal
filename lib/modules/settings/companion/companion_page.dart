import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:journal/config/theme.dart';

import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';

import 'companion_controller.dart';
import 'companion_protocol.dart';

String companionPhaseLabel(CompanionPhase phase) => switch (phase) {
  CompanionPhase.loading => 'Reading protected trust',
  CompanionPhase.idle => 'No computer connected',
  CompanionPhase.trusted => 'Trusted · disconnected',
  CompanionPhase.connecting => 'Checking computer',
  CompanionPhase.connected => 'Connected · identity verified',
  CompanionPhase.pairing => 'Waiting for desktop approval',
  CompanionPhase.unavailable => 'Computer unavailable',
  CompanionPhase.permissionDenied => 'Local network permission needed',
  CompanionPhase.incompatible => 'Update required',
  CompanionPhase.identityChanged => 'Identity verification failed',
  CompanionPhase.revoked => 'Trust revoked or not recognized',
};

class CompanionNavigationTile extends ConsumerWidget {
  const CompanionNavigationTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(companionControllerProvider);
    final colors = context.colors;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.computer_rounded, color: colors.primary, size: 22),
      ),
      title: Text(
        'Local AI computer',
        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        companionPhaseLabel(connection.phase),
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: colors.primary),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const CompanionPage())),
    );
  }
}

class CompanionPage extends ConsumerWidget {
  const CompanionPage({super.key});
  Future<void> _pair(
    BuildContext context,
    WidgetRef ref, {
    bool paste = false,
    String? expectedId,
  }) async {
    final raw = paste
        ? await _paste(context)
        : await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const CompanionScannerPage()),
          );
    if (raw == null || !context.mounted) return;
    try {
      final code = PairingCode.parse(raw);
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _VerifyComputerDialog(code: code),
      );
      if (name == null || !context.mounted) return;
      await ref
          .read(companionControllerProvider.notifier)
          .pair(raw, name, expectedId: expectedId);
    } on CompanionFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<String?> _paste(BuildContext context) => showDialog<String>(
    context: context,
    builder: (_) => const _PasteCodeDialog(),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companionControllerProvider);
    final controller = ref.read(companionControllerProvider.notifier);
    final selected = state.selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Local AI computer')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Connect to your own computer',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open Journal Companion → Connect a phone on your computer. Keep both devices on the same Wi-Fi. After setup this connection works without internet or Google sign-in. No journal content is sent by this screen.',
          ),
          const SizedBox(height: 20),
          Semantics(
            liveRegion: true,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companionPhaseLabel(state.phase),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (state.message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(state.message!),
                      ),
                    if (state.verification != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Phone verification code: ${state.verification}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text(
                        'Compare this code on the desktop before approving.',
                      ),
                    ],
                    if (state.phase == CompanionPhase.connected) ...[
                      const SizedBox(height: 12),
                      for (final capability
                          in (state.status?['capabilities'] as List? ??
                              const []))
                        Text(
                          '${capability['id'] == 'text' ? 'Writing model' : capability['id']}: ${capability['status']}\n${capability['reason']}',
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'Transport and model readiness are separate. A connected computer may still need a model download or load.',
                      ),
                    ],
                    if (state.busy && state.phase == CompanionPhase.pairing)
                      TextButton(
                        onPressed: controller.cancelPairing,
                        child: const Text('Cancel pairing'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: state.busy ? null : () => _pair(context, ref),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan desktop QR'),
              ),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => _pair(context, ref, paste: true),
                child: const Text('Paste pairing code'),
              ),
              OutlinedButton(
                onPressed: state.busy || state.scanning
                    ? null
                    : controller.discover,
                child: Text(
                  state.scanning
                      ? 'Finding computers…'
                      : 'Find nearby computers',
                ),
              ),
              if (state.phase == CompanionPhase.unavailable &&
                  state.computers.isEmpty)
                TextButton(
                  onPressed: controller.restore,
                  child: const Text('Reload saved trust'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            key: const ValueKey('companion-ai-task-history'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: const Text('AI task history'),
            subtitle: const Text('Recover summaries and review recent results'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SummaryHistoryPage(),
              ),
            ),
          ),
          if (state.discovered.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Nearby · names are unverified',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final computer in state.discovered)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.computer),
                title: Text(computer.name),
                subtitle: Text(
                  computer.version == '1'
                      ? 'Scan this computer’s QR to verify its identity'
                      : 'Incompatible protocol · update both apps',
                ),
                onTap: state.busy || computer.version != '1'
                    ? null
                    : () => _pair(context, ref, expectedId: computer.id),
              ),
          ],
          if (state.computers.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Trusted computers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            RadioGroup<String>(
              groupValue: state.selectedId,
              onChanged: (id) {
                if (!state.busy && id != null) controller.select(id);
              },
              child: Column(
                children: [
                  for (final computer in state.computers)
                    RadioListTile<String>(
                      value: computer.id,
                      enabled: !state.busy,
                      title: Text(computer.name),
                      subtitle: Text(
                        computer.enabled
                            ? 'Trust remembered on this phone'
                            : 'Automatic connection paused',
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 12),
            SelectableText('Verified identity\n${selected.pin}'),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => selected.enabled
                            ? controller.reconnect()
                            : controller.disconnect(resume: true),
                  child: Text(
                    selected.enabled ? 'Retry connection' : 'Reconnect',
                  ),
                ),
                if (selected.enabled)
                  TextButton(
                    onPressed: state.busy ? null : controller.disconnect,
                    child: const Text('Disconnect'),
                  ),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Forget ${selected.name}?'),
                              content: const Text(
                                'Remove this phone’s trust. If reachable, the computer will also revoke this phone and delete its retained work. If offline, revoke it later on the desktop. You will need a fresh QR to pair again.',
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
                  child: const Text('Forget computer'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          SwitchListTile(
            key: const ValueKey('daily-questions-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Daily diary questions'),
            subtitle: const Text(
              'Lets you ask for one optional question on today’s diary page. It uses up to 8 text entries from the past week and today, sent only to your paired computer, and never runs in the background. Turning this off deletes this phone’s question history.',
            ),
            value: ref.watch(dailyQuestionEnabledProvider),
            onChanged: (value) =>
                ref.read(dailyQuestionProvider.notifier).setEnabled(value),
          ),
          const SizedBox(height: 24),
          const Text(
            'If discovery fails',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const Text(
            'Scan a fresh QR or paste its full code; a short numeric code alone cannot locate a computer. Allow Local Network access for Journal in iPhone Settings. On Android, allow Camera when scanning. A denied camera can be bypassed with Paste pairing code. Guest Wi-Fi, client isolation, VPNs and some phone hotspots block direct connections; try an ordinary private Wi-Fi network. This preview needs IPv4.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Disconnect keeps trust and accepted work. Desktop revocation removes access and retained work. Trust stays out of Google Drive and journal sync. Readiness is checked again after a restart or network change; no scans run while the app is in the background.',
          ),
        ],
      ),
    );
  }
}

class _VerifyComputerDialog extends StatefulWidget {
  const _VerifyComputerDialog({required this.code});
  final PairingCode code;
  @override
  State<_VerifyComputerDialog> createState() => _VerifyComputerDialogState();
}

class _VerifyComputerDialogState extends State<_VerifyComputerDialog> {
  final name = TextEditingController(text: 'My Journal phone');
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verify your computer'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.code.name),
          const SizedBox(height: 8),
          const Text(
            'Compare this identity with the companion before continuing:',
          ),
          SelectableText(widget.code.pin),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            maxLength: 48,
            decoration: const InputDecoration(labelText: 'Name for this phone'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, name.text),
        child: const Text('Verify & request trust'),
      ),
    ],
  );
}

class _PasteCodeDialog extends StatefulWidget {
  const _PasteCodeDialog();
  @override
  State<_PasteCodeDialog> createState() => _PasteCodeDialogState();
}

class _PasteCodeDialogState extends State<_PasteCodeDialog> {
  final code = TextEditingController();
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Paste full desktop code'),
    content: TextField(
      controller: code,
      maxLines: 6,
      maxLength: 8192,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(
        hintText:
            'Copy the full pairing code shown below the QR on your computer.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, code.text),
        child: const Text('Continue'),
      ),
    ],
  );
}

class CompanionScannerPage extends StatefulWidget {
  const CompanionScannerPage({super.key});
  @override
  State<CompanionScannerPage> createState() => _CompanionScannerPageState();
}

class _CompanionScannerPageState extends State<CompanionScannerPage> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool captured = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan the desktop QR')),
    body: MobileScanner(
      controller: controller,
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (captured || raw == null) return;
        captured = true;
        Navigator.pop(context, raw);
      },
      errorBuilder: (context, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Camera unavailable or permission denied. Allow Camera in system Settings, or go back and paste the desktop pairing code.',
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Use pairing code instead'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
