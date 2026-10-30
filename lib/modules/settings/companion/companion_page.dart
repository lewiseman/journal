import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';

import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/voice/views/pages/reply_voice_page.dart';

import '../../local_ai/core/ai_settings.dart';
import '../../local_ai/core/engine_registry.dart';
import '../../local_ai/ui/device_mode_selector.dart';
import '../../local_ai/ui/ai_studio_material.dart';
import '../../local_ai/ui/device_task_card.dart';
import 'companion_connection_guide.dart';
import 'companion_controller.dart';
import 'companion_detail_pages.dart';
import 'companion_hub_widgets.dart';
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
    final mode = ref.watch(onDeviceEngineProvider) == null
        ? AiMode.companion
        : ref.watch(aiSettingsProvider).mode;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          switch (mode) {
            AiMode.device => Icons.phone_iphone_rounded,
            AiMode.auto => Icons.swap_horiz_rounded,
            AiMode.companion => Icons.computer_rounded,
          },
          color: colors.primary,
          size: 22,
        ),
      ),
      title: Text(
        'Local AI',
        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        switch (mode) {
          AiMode.device => 'On this phone',
          AiMode.auto =>
            connection.phase == CompanionPhase.connected
                ? 'Auto · Companion connected'
                : 'Auto · Phone when ready',
          AiMode.companion => companionPhaseLabel(connection.phase),
        },
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

class CompanionPage extends ConsumerStatefulWidget {
  const CompanionPage({super.key});

  @override
  ConsumerState<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends ConsumerState<CompanionPage> {
  final _setupKey = GlobalKey();

  void _showSetup() {
    final target = _setupKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: .04,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _pair(
    BuildContext context,
    WidgetRef ref, {
    bool paste = false,
    String? expectedId,
  }) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    String? raw;
    if (paste) {
      raw = await _paste(context);
    } else {
      final scan = await Navigator.of(context).push<_ScanResult>(
        MaterialPageRoute(builder: (_) => const CompanionScannerPage()),
      );
      if (!context.mounted) return;
      raw = scan?.useCode == true ? await _paste(context) : scan?.raw;
    }
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
  Widget build(BuildContext context) =>
      QvacAssistantPage(enabled: false, child: _buildPage(context, ref));

  Widget _buildPage(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companionControllerProvider);
    final hasEngine = ref.watch(onDeviceEngineProvider) != null;
    final mode = hasEngine
        ? ref.watch(aiSettingsProvider).mode
        : AiMode.companion;
    final connected = state.phase == CompanionPhase.connected;
    final phoneFirst =
        mode == AiMode.device || (mode == AiMode.auto && !connected);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final setup = Column(
      key: ValueKey(phoneFirst ? 'phone-setup' : 'computer-setup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phoneFirst) ...[
          const DeviceAiSection(key: ValueKey('ai-phone-setup')),
          const SizedBox(height: 20),
          _alternativeSetup(
            context,
            id: 'companion',
            icon: Icons.desktop_mac_rounded,
            title: 'Companion extras',
            subtitle:
                'Search by meaning, voice & scans still need your computer.',
            status: connected ? 'Connected' : null,
            builder: (context) => _companionSetup(context, ref, state),
          ),
        ] else ...[
          _companionSetup(context, ref, state),
          if (hasEngine) ...[
            const SizedBox(height: 20),
            _alternativeSetup(
              context,
              id: 'device',
              icon: Icons.phone_iphone_rounded,
              title: 'Take AI with you',
              subtitle: 'Prepare phone models for offline writing & images.',
              builder: (_) => const DeviceAiSection(),
            ),
          ],
        ],
      ],
    );
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: context.colors.surface,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hasEngine) const _LocalAiIntro(),
                  DeviceModeSelector(onSetup: _showSetup),
                  if (hasEngine)
                    const AiStudioRule(label: 'a place to begin')
                  else
                    const SizedBox(height: 24),
                  if (mode == AiMode.auto) ...[
                    AiStudioPaper(
                      key: const ValueKey('ai-auto-status'),
                      padding: const EdgeInsets.all(20),
                      seed: 58,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            connected
                                ? Icons.desktop_mac_rounded
                                : Icons.phone_iphone_rounded,
                            color: context.colors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                connected
                                    ? 'Your computer is connected. Auto prefers Companion; set up phone models below for when you’re away.'
                                    : 'Your computer is offline. Auto can use the phone models you set up below.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(height: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  KeyedSubtree(
                    key: _setupKey,
                    child: reduced
                        ? setup
                        : AnimatedSize(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeInOutCubic,
                            alignment: Alignment.topCenter,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, .025),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              // Retired controls cannot receive taps during a transition.
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  for (final child in previous)
                                    ExcludeSemantics(
                                      child: IgnorePointer(child: child),
                                    ),
                                  ?current,
                                ],
                              ),
                              child: setup,
                            ),
                          ),
                  ),
                  if (hasEngine) ...[
                    const SizedBox(height: 8),
                    const AiTaskPreferences(),
                  ],
                  const AiStudioRule(label: 'the little details'),
                  CompanionShortcuts(
                    onVoice: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReplyVoicePage(),
                      ),
                    ),
                    onHistory: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SummaryHistoryPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CompanionPreferenceCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CompanionPreferencesPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _alternativeSetup(
    BuildContext context, {
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required WidgetBuilder builder,
    String? status,
  }) => ExpansionTile(
    key: ValueKey('ai-alternative-$id'),
    leading: Icon(icon, color: context.colors.primary),
    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    shape: const Border(),
    collapsedShape: const Border(),
    title: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${status == null ? '' : '$status · '}$subtitle',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
    ),
    children: [Builder(builder: builder)],
  );

  Widget _companionSetup(
    BuildContext context,
    WidgetRef ref,
    CompanionState state,
  ) {
    final controller = ref.read(companionControllerProvider.notifier);
    return Column(
      key: const ValueKey('ai-companion-setup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompanionConnectionGuide(
          connection: state,
          onScan: () => _pair(context, ref),
          onReconnect: () => state.selected?.enabled == false
              ? controller.disconnect(resume: true)
              : controller.reconnect(),
          onCancel: controller.cancelPairing,
        ),
        if (state.message != null && state.phase != CompanionPhase.pairing) ...[
          const SizedBox(height: 16),
          _connectionMessage(context, state),
        ],
        if (state.phase == CompanionPhase.connected) ...[
          const SizedBox(height: 24),
          CompanionReadinessStrip(state: state),
        ],
        if (state.computers.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Your computers',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          CompanionComputerCard(
            state: state,
            onTap: () => _openDevices(context, ref),
          ),
        ] else ...[
          const SizedBox(height: 12),
          _fallbackControls(context, ref, state),
        ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            TextButton.icon(
              key: const ValueKey('companion-help'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CompanionHelpPage(),
                ),
              ),
              icon: const Icon(Icons.help_outline_rounded, size: 19),
              label: const Text('Need help?'),
            ),
            TextButton.icon(
              key: const ValueKey('companion-connection-details'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CompanionPrivacyPage(),
                ),
              ),
              icon: const Icon(Icons.shield_outlined, size: 19),
              label: const Text('Connection details'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openDevices(BuildContext context, WidgetRef ref) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CompanionDevicesPage(
            onPair: (pageContext, {bool paste = false, String? expectedId}) =>
                _pair(pageContext, ref, paste: paste, expectedId: expectedId),
          ),
        ),
      );

  Widget _fallbackControls(
    BuildContext context,
    WidgetRef ref,
    CompanionState state,
  ) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [
      TextButton.icon(
        key: const ValueKey('companion-paste'),
        onPressed: state.busy ? null : () => _pair(context, ref, paste: true),
        icon: const Icon(Icons.content_paste_rounded),
        label: const Text('Use a code'),
      ),
      TextButton.icon(
        key: const ValueKey('companion-discover'),
        onPressed: state.busy || state.scanning
            ? null
            : () {
                ref.read(companionControllerProvider.notifier).discover();
                _openDevices(context, ref);
              },
        icon: const Icon(Icons.radar_rounded),
        label: Text(state.scanning ? 'Looking…' : 'Find computer'),
      ),
    ],
  );

  Widget _connectionMessage(BuildContext context, CompanionState state) {
    final colors = context.colors;
    final problem = const {
      CompanionPhase.unavailable,
      CompanionPhase.permissionDenied,
      CompanionPhase.incompatible,
      CompanionPhase.identityChanged,
      CompanionPhase.revoked,
    }.contains(state.phase);
    final ink = problem ? colors.onErrorContainer : colors.onSurface;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: problem
              ? colors.errorContainer.withValues(alpha: .45)
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    companionPhaseLabel(state.phase),
                    style: TextStyle(fontWeight: FontWeight.w600, color: ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(state.message!),
          ],
        ),
      ),
    );
  }
}

class _LocalAiIntro extends StatelessWidget {
  const _LocalAiIntro();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Your little\nthinking space.',
          style: studioTitle(context, size: 28),
        ),
      ),
      const SizedBox(width: 10),
      ExcludeSemantics(
        child: Image.asset(
          'assets/images/ai_studio_computer.png',
          width: 120,
          height: 110,
        ),
      ),
    ],
  );
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
    icon: const Icon(Icons.verified_user_outlined, size: 32),
    title: const Text('Is this your computer?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.computer_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.code.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Check this identity in Journal Companion. Continue only if it matches.',
          ),
          const SizedBox(height: 8),
          SelectableText(
            widget.code.pin,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
        key: const ValueKey('companion-confirm-identity'),
        onPressed: () => Navigator.pop(context, name.text),
        child: const Text('It matches · continue'),
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
    icon: const Icon(Icons.content_paste_rounded, size: 32),
    title: const Text('Use a code'),
    content: TextField(
      controller: code,
      maxLines: 6,
      maxLength: 8192,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      decoration: const InputDecoration(
        labelText: 'Full computer code',
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

class _ScanResult {
  const _ScanResult({this.raw, this.useCode = false});
  final String? raw;
  final bool useCode;
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
    appBar: AppBar(title: const Text('Scan QR')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Row(
            children: [
              Icon(Icons.laptop_mac_rounded, size: 32),
              SizedBox(width: 16),
              Expanded(child: Text('Point at the QR on your computer.')),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: controller,
                onDetect: (capture) {
                  final raw = capture.barcodes.firstOrNull?.rawValue;
                  if (captured || raw == null) return;
                  captured = true;
                  Navigator.pop(context, _ScanResult(raw: raw));
                },
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.no_photography_outlined, size: 56),
                        const SizedBox(height: 16),
                        const Text(
                          'Camera unavailable. Allow Camera in Settings, or use the computer’s code.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const IgnorePointer(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: .72,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.fromBorderSide(
                            BorderSide(color: Colors.white70, width: 3),
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () =>
                  Navigator.pop(context, const _ScanResult(useCode: true)),
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Use a code instead'),
            ),
          ),
        ),
      ],
    ),
  );
}
