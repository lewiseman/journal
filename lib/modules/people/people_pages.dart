import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/more/views/widgets/people_artwork.dart';
import 'package:journal/utils/navigation_helper.dart';

import 'people_controller.dart';
import 'people_models.dart';
import 'widgets/burning_paper.dart';
import 'widgets/friend_avatar.dart';
import 'widgets/people_paper.dart';
import 'widgets/sealed_envelope.dart';

Future<void> _action(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is PeopleFailure
                ? error.message
                : const PeopleFailure().message,
          ),
        ),
      );
    }
  }
}

class _Status extends ConsumerWidget {
  const _Status();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peopleControllerProvider);
    final palette = PeoplePalette.of(context);
    if (!state.supported) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: PaperSheet(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.phone_android_rounded, color: palette.clay),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Friends works on Android phones for now.'),
              ),
            ],
          ),
        ),
      );
    }
    if (state.loading || state.busy) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: PeopleChip(
            label: 'Connecting…',
            icon: SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: palette.clay,
              ),
            ),
          ),
        ),
      );
    }
    if (state.message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: PaperSheet(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.wifi_off_rounded, color: palette.wax, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state.message!,
                    style: TextStyle(color: palette.wax),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: palette.ink),
                onPressed: () => _action(context, () async {
                  final controller = ref.read(
                    peopleControllerProvider.notifier,
                  );
                  await controller.restore();
                  await controller.connect();
                }),
                child: const Text('Retry connection'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PeoplePage extends ConsumerWidget {
  const PeoplePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peopleControllerProvider);
    final palette = PeoplePalette.of(context);
    final unopened = state.notes.where((n) => !n.opened).toList();
    final canAdd = state.supported && !state.loading;
    return PeopleScaffold(
      title: 'Friends',
      children: [
        const _Status(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your friends', style: peopleHand(context, size: 38)),
                  const SizedBox(height: 4),
                  Text(
                    'A small note, just between you.\nKeep both apps open to exchange notes.',
                    style: TextStyle(color: palette.muted, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const SizedBox(width: 76, height: 76, child: PeopleEntryArtwork()),
          ],
        ),
        const SizedBox(height: 18),
        InkButton(
          key: const ValueKey('people-add-friend'),
          label: 'Add friend',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: canAdd
              ? () => context.nav.push(const AddFriendPage())
              : null,
        ),
        if (state.candidates.isNotEmpty) ...[
          const SizedBox(height: 20),
          _KnockCard(
            name: state.candidates.first.name,
            friendKey: state.candidates.first.key,
            onTap: () => context.nav.push(const AddFriendPage()),
          ),
        ],
        if (unopened.isNotEmpty) ...[
          const SizedBox(height: 24),
          PeopleHeading(
            'Waiting for you',
            trailing: WaxBadge(count: unopened.length),
          ),
          EnvelopeStack(
            children: [
              for (final (i, note) in unopened.indexed)
                _NoteEnvelope(id: note.id, tilt: EnvelopeStack.tiltFor(i)),
            ],
          ),
        ],
        const SizedBox(height: 24),
        const PeopleHeading('Friends'),
        if (state.friends.isEmpty)
          CustomPaint(
            painter: _DashedBorder(palette.muted.withValues(alpha: .4)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Your people will appear here. Create an invitation, or scan or paste one from a friend.',
                style: TextStyle(color: palette.muted, height: 1.4),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 14.0;
              final columns = constraints.maxWidth > 440 ? 3 : 2;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final (i, person) in state.friends.indexed)
                    SizedBox(
                      width: width,
                      child: _FriendCard(
                        person: person,
                        unopened: state.notes
                            .where(
                              (n) => n.friendKey == person.key && !n.opened,
                            )
                            .length,
                        tilt: (i.isEven ? -1 : 1) * .012,
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: palette.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                peoplePrivacy,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.person,
    required this.unopened,
    required this.tilt,
  });
  final Person person;
  final int unopened;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    return Transform.rotate(
      angle: tilt,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PaperSheet(
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () =>
                    context.nav.push(FriendDetailsPage(friendKey: person.key)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FriendAvatar(
                        friendKey: person.key,
                        name: person.name,
                        size: 64,
                        hero: true,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: peopleHand(context, size: 26),
                      ),
                      Text(
                        unopened == 0
                            ? 'No notes waiting'
                            : unopened == 1
                            ? '1 unopened note'
                            : '$unopened unopened notes',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: unopened == 0 ? palette.muted : palette.wax,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (unopened > 0)
            Positioned(
              top: -8,
              right: -6,
              child: WaxBadge(count: unopened, size: 28),
            ),
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(8),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 11) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _KnockCard extends StatelessWidget {
  const _KnockCard({
    required this.name,
    required this.friendKey,
    required this.onTap,
  });
  final String name, friendKey;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    return PaperSheet(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          FriendAvatar(friendKey: friendKey, name: name, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Knock knock — $name',
                  style: peopleHand(context, size: 24),
                ),
                Text(
                  'wants to be your friend',
                  style: TextStyle(color: palette.muted),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: palette.wax),
            onPressed: onTap,
            child: const Text('Review friend request'),
          ),
        ],
      ),
    );
  }
}

class AddFriendPage extends ConsumerStatefulWidget {
  const AddFriendPage({super.key});
  @override
  ConsumerState<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends ConsumerState<AddFriendPage> {
  final _paste = TextEditingController();
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _paste.clear();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _accept(String raw) async {
    try {
      final invite = FriendInvitation.parse(raw);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Add ${invite.name}?'),
          content: const Text(
            'Only accept an invitation shared by the person you intend to add. Both apps must stay open while they confirm.',
          ),
          actions: [
            TextButton(
              onPressed: () => context.nav.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.nav.pop(true),
              child: const Text('Accept invitation'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      _paste.clear();
      final success = await ref
          .read(peopleControllerProvider.notifier)
          .acceptInvite(raw);
      if (success && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Friend added')));
        context.nav.pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PeopleFailure
                  ? error.message
                  : 'Could not read this invitation.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(peopleControllerProvider);
    final controller = ref.read(peopleControllerProvider.notifier);
    final palette = PeoplePalette.of(context);
    final invite = state.invite;
    final canReceive =
        state.supported && !state.busy && state.candidates.isEmpty;
    return PeopleScaffold(
      title: 'Add friend',
      children: [
        const _Status(),
        PaperSheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Invite someone', style: peopleHand(context, size: 30)),
              const SizedBox(height: 6),
              Text(
                'Show a QR code nearby, or copy an invitation to share through another app. Come back to Journal so your friend can connect.',
                style: TextStyle(color: palette.muted, height: 1.4),
              ),
              const SizedBox(height: 18),
              if (invite == null || invite.expired)
                InkButton(
                  label: 'Create invitation',
                  icon: Icons.qr_code_rounded,
                  onPressed: canReceive ? controller.createInvite : null,
                )
              else
                _InviteTicket(
                  invite: invite,
                  onCopy: () async {
                    await Clipboard.setData(
                      ClipboardData(text: invite.encode()),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Invitation copied. Return here after sharing.',
                          ),
                        ),
                      );
                    }
                  },
                  onCancel: controller.cancelInvite,
                ),
            ],
          ),
        ),
        for (final person in state.candidates) ...[
          const SizedBox(height: 18),
          PaperSheet(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FriendAvatar(
                      friendKey: person.key,
                      name: person.name,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${person.name} wants to be your friend',
                        style: peopleHand(context, size: 26),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Confirm only if this is the person you shared your invitation with.',
                  style: TextStyle(color: palette.muted, height: 1.4),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    InkButton(
                      label: 'Confirm friend',
                      expand: false,
                      onPressed: state.busy
                          ? null
                          : () => controller.confirm(person, true),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: palette.muted,
                      ),
                      onPressed: state.busy
                          ? null
                          : () => controller.confirm(person, false),
                      child: const Text('Decline'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        PaperSheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Have an invitation?', style: peopleHand(context, size: 30)),
              const SizedBox(height: 14),
              InkButton(
                label: 'Scan invitation',
                icon: Icons.qr_code_scanner_rounded,
                outlined: true,
                onPressed: canReceive
                    ? () async {
                        final raw = await context.nav.push<String>(
                          const PeopleScannerPage(),
                        );
                        if (raw != null && mounted) await _accept(raw);
                      }
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: palette.rule)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or',
                        style: peopleHand(
                          context,
                          size: 20,
                          color: palette.muted,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: palette.rule)),
                  ],
                ),
              ),
              TextField(
                controller: _paste,
                maxLength: 2048,
                minLines: 2,
                maxLines: 4,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Paste invitation',
                  filled: true,
                  fillColor: palette.desk.withValues(alpha: .6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              InkButton(
                label: 'Accept pasted invitation',
                onPressed: state.supported && !state.busy
                    ? () => _accept(_paste.text)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'While connecting, wait here for your friend to confirm. Invitations expire after five minutes.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.muted),
        ),
      ],
    );
  }
}

/// The QR code inside a ring that empties as the invitation expires.
class _InviteTicket extends StatelessWidget {
  const _InviteTicket({
    required this.invite,
    required this.onCopy,
    required this.onCancel,
  });
  final FriendInvitation invite;
  final VoidCallback onCopy, onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    final seconds = invite.expires
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 300);
    final left =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Column(
      children: [
        SizedBox.square(
          dimension: 284,
          child: CustomPaint(
            painter: _CountdownRing(
              fraction: seconds / 300,
              track: palette.rule,
              color: seconds < 60 ? palette.wax : palette.clay,
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: invite.encode(),
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: Color(0xFF3A2E28),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Color(0xFF3A2E28),
                  ),
                  semanticsLabel: 'Private friend invitation QR code',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: 'Expires in $seconds seconds',
          excludeSemantics: true,
          child: PeopleChip(
            label: 'Expires in $left',
            icon: Icon(Icons.timer_outlined, size: 16, color: palette.clay),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: palette.ink),
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy invitation'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: palette.muted),
              onPressed: onCancel,
              child: const Text('Cancel invitation'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CountdownRing extends CustomPainter {
  const _CountdownRing({
    required this.fraction,
    required this.track,
    required this.color,
  });
  final double fraction;
  final Color track, color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(4);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = track;
    canvas.drawRRect(rrect, base);
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * fraction),
      base
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CountdownRing old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

class PeopleScannerPage extends StatefulWidget {
  const PeopleScannerPage({super.key});
  @override
  State<PeopleScannerPage> createState() => _PeopleScannerPageState();
}

class _PeopleScannerPageState extends State<PeopleScannerPage> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _done = false;
  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => QvacAssistantPage(
    enabled: false,
    child: Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          'Scan invitation',
          style: peopleHand(context, size: 28, color: Colors.white),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: (capture) {
              if (_done) return;
              final raw = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .firstOrNull;
              if (raw == null) return;
              _done = true;
              HapticFeedback.mediumImpact();
              context.nav.pop(raw);
            },
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable. Go back and paste an invitation instead.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: CustomPaint(
                size: const Size.square(250),
                painter: _ViewfinderPainter(),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Point at your friend’s invitation',
              textAlign: TextAlign.center,
              style: peopleHand(context, size: 24, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const arm = 34.0, r = 18.0;
    final w = size.width, h = size.height;
    for (final (x, y, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (w, 0.0, -1.0, 1.0),
      (0.0, h, 1.0, -1.0),
      (w, h, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + sy * arm)
          ..lineTo(x, y + sy * r)
          ..quadraticBezierTo(x, y, x + sx * r, y)
          ..lineTo(x + sx * arm, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => false;
}

class FriendDetailsPage extends ConsumerWidget {
  const FriendDetailsPage({super.key, required this.friendKey});
  final String friendKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peopleControllerProvider);
    final palette = PeoplePalette.of(context);
    final person = state.person(friendKey);
    final notes = state.notes
        .where((n) => n.friendKey == friendKey && !n.opened)
        .toList();
    return PeopleScaffold(
      title: person?.name ?? 'Friend',
      children: [
        const _Status(),
        if (person == null)
          const Text('This friend has been removed.')
        else ...[
          const SizedBox(height: 8),
          Center(
            child: FriendAvatar(
              friendKey: person.key,
              name: person.name,
              size: 116,
              hero: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            person.name,
            textAlign: TextAlign.center,
            style: peopleHand(context, size: 44),
          ),
          Text(
            'Every note between you burns after reading.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted),
          ),
          const SizedBox(height: 24),
          InkButton(
            key: const ValueKey('people-write-note'),
            label: 'Write a note',
            icon: Icons.edit_rounded,
            onPressed: () =>
                context.nav.push(WritePeopleNotePage(friendKey: friendKey)),
          ),
          const SizedBox(height: 32),
          PeopleHeading(
            'Unopened notes',
            trailing: notes.isEmpty ? null : WaxBadge(count: notes.length),
          ),
          if (notes.isEmpty)
            CustomPaint(
              painter: _DashedBorder(palette.muted.withValues(alpha: .4)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      Icons.mark_email_unread_outlined,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No unopened notes. Both apps must be open to receive one.',
                        style: TextStyle(color: palette.muted, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            EnvelopeStack(
              children: [
                for (final (i, note) in notes.indexed)
                  _NoteEnvelope(id: note.id, tilt: EnvelopeStack.tiltFor(i)),
              ],
            ),
          const SizedBox(height: 40),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: palette.wax.withValues(alpha: .85),
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Remove ${person.name}?'),
                    content: const Text(
                      'Their unopened notes will disappear. You will need a new invitation to connect again.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => context.nav.pop(false),
                        child: const Text('Keep friend'),
                      ),
                      FilledButton(
                        onPressed: () => context.nav.pop(true),
                        child: const Text('Remove friend'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await _action(context, () async {
                    await ref
                        .read(peopleControllerProvider.notifier)
                        .remove(person);
                    if (context.mounted) context.nav.pop();
                  });
                }
              },
              icon: const Icon(Icons.person_remove_outlined),
              label: const Text('Remove friend'),
            ),
          ),
        ],
      ],
    );
  }
}

class WritePeopleNotePage extends ConsumerStatefulWidget {
  const WritePeopleNotePage({super.key, required this.friendKey});
  final String friendKey;
  @override
  ConsumerState<WritePeopleNotePage> createState() =>
      _WritePeopleNotePageState();
}

class _WritePeopleNotePageState extends ConsumerState<WritePeopleNotePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _text = TextEditingController();
  late final _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _sending = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _text.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _text.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.removeListener(_changed);
    _text.clear();
    _text.dispose();
    _fly.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final text = _text.text;
    _text.clear();
    HapticFeedback.lightImpact();
    final flight = MediaQuery.disableAnimationsOf(context)
        ? Future<void>.value()
        : _fly.forward(from: 0).orCancel.catchError((_) {});
    final success = await ref
        .read(peopleControllerProvider.notifier)
        .send(widget.friendKey, text);
    await flight;
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Send attempted. Delivery is not guaranteed.'
              : 'Could not send. The note was discarded.',
        ),
      ),
    );
    context.nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(peopleControllerProvider);
    ref.listen(
      peopleControllerProvider.select((s) => s.draftEpoch),
      (_, _) => _text.clear(),
    );
    final palette = PeoplePalette.of(context);
    final person = state.person(widget.friendKey);
    final words = peopleWordCount(_text.text);
    final bytes = utf8.encode(_text.text).length;
    const lineHeight = 30.0;
    final body = peopleSerif(context, size: 17);
    return PeopleScaffold(
      title: 'Write a note',
      children: [
        if (person == null)
          const Text('This friend is no longer available.')
        else ...[
          Row(
            children: [
              FriendAvatar(
                friendKey: person.key,
                name: person.name,
                size: 44,
                hero: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'For ${person.name}',
                  style: peopleHand(context, size: 34),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _fly,
            builder: (context, child) {
              final t = Curves.easeInCubic.transform(_fly.value);
              return Opacity(
                opacity: 1 - t,
                child: Transform.translate(
                  offset: Offset(t * 120, -t * 220),
                  child: Transform.rotate(
                    angle: t * .35,
                    child: Transform.scale(scale: 1 - t * .55, child: child),
                  ),
                ),
              );
            },
            child: PaperSheet(
              ruled: true,
              lineHeight: lineHeight,
              padding: const EdgeInsets.fromLTRB(28, 12, 18, 12),
              child: TextField(
                key: const ValueKey('people-note-input'),
                controller: _text,
                enabled: !_sending,
                minLines: 10,
                maxLines: 16,
                maxLength: 8192,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                cursorColor: palette.wax,
                style: body,
                strutStyle: StrutStyle(
                  fontFamily: body.fontFamily,
                  fontSize: 17,
                  height: lineHeight / 17,
                  forceStrutHeight: true,
                ),
                decoration: InputDecoration(
                  hintText: 'A little something for your friend…',
                  hintStyle: body.copyWith(color: palette.muted),
                  border: InputBorder.none,
                  isCollapsed: true,
                  counterText: '',
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _WordMeter(words: words, bytes: bytes),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: PeopleChip(
              icon: const FlameIcon(size: 14),
              label:
                  '${peopleReadingTime(_text.text).inSeconds} seconds to read, starting when opened.',
            ),
          ),
          const SizedBox(height: 20),
          InkButton(
            key: const ValueKey('people-send-note'),
            label: _sending ? 'Attempting to send…' : 'Send',
            icon: Icons.send_rounded,
            onPressed:
                !_sending &&
                    !state.busy &&
                    state.foreground &&
                    validPeopleNote(_text.text)
                ? _send
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            'Keep both apps open. This makes one attempt and discards the draft. Nothing is saved for later delivery.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.muted),
          ),
        ],
      ],
    );
  }
}

class _WordMeter extends StatelessWidget {
  const _WordMeter({required this.words, required this.bytes});
  final int words, bytes;
  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    final fraction = max(words / 500, bytes / 8192).clamp(0.0, 1.0);
    final over = words > 500 || bytes > 8192;
    final color = over
        ? palette.wax
        : Color.lerp(palette.clay, palette.wax, max(0, fraction - .8) * 5)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: palette.rule),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: ColoredBox(color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$words / 500 words · $bytes / 8192 bytes',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: over ? palette.wax : palette.muted),
        ),
      ],
    );
  }
}

class _NoteEnvelope extends ConsumerWidget {
  const _NoteEnvelope({required this.id, this.tilt = 0});
  final int id;
  final double tilt;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peopleControllerProvider);
    final note = state.note(id);
    if (note == null || note.opened) return const SizedBox.shrink();
    return SealedEnvelope(
      friendKey: note.friendKey,
      name: state.person(note.friendKey)?.name ?? 'a friend',
      seconds: note.duration.inSeconds,
      tilt: tilt,
      onOpen: () {
        ref.read(peopleControllerProvider.notifier).openNote(id);
        context.nav.push(ReadPeopleNotePage(noteId: id));
      },
    );
  }
}

class ReadPeopleNotePage extends ConsumerStatefulWidget {
  const ReadPeopleNotePage({super.key, required this.noteId});
  final int noteId;
  @override
  ConsumerState<ReadPeopleNotePage> createState() => _ReadPeopleNotePageState();
}

class _ReadPeopleNotePageState extends ConsumerState<ReadPeopleNotePage>
    with WidgetsBindingObserver {
  late final PeopleController _controller;
  PeopleNote? _note;
  bool _wasVisible = false;
  @override
  void initState() {
    super.initState();
    _controller = ref.read(peopleControllerProvider.notifier);
    _note = ref.read(peopleControllerProvider).note(widget.noteId);
    WidgetsBinding.instance.addObserver(this);
    HapticFeedback.lightImpact();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _controller.discardNote(widget.noteId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Drop the body now; defer the provider notification until route teardown ends.
    _note?.discard();
    scheduleMicrotask(() {
      _controller.discardNote(widget.noteId);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(peopleControllerProvider);
    final palette = PeoplePalette.of(context);
    final note = state.note(widget.noteId);
    final visible =
        note != null &&
        note.opened &&
        note.text.isNotEmpty &&
        state.foreground &&
        note.remaining > Duration.zero;
    if (_wasVisible && !visible) HapticFeedback.mediumImpact();
    _wasVisible = visible;
    const lineHeight = 30.0;
    final body = peopleSerif(context, size: 17);
    return PeopleScaffold(
      title: visible
          ? 'From ${state.person(note.friendKey)?.name ?? 'a friend'}'
          : 'Note disappeared',
      // The sheet sits in a wide margin so its shadow burns with it.
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
      children: [
        if (visible) ...[
          Row(
            children: [
              const SizedBox(width: 20),
              _Countdown(note: note),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Closing this page discards the note.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.muted),
                ),
              ),
              const SizedBox(width: 20),
            ],
          ),
          const SizedBox(height: 6),
          BurningPaper(
            seed: note.id,
            inset: 30,
            progress: () =>
                1 -
                note.remaining.inMilliseconds / note.duration.inMilliseconds,
            child: Padding(
              // Keeps the sheet's shadow inside the burn mask.
              padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
              child: PaperSheet(
                ruled: true,
                lineHeight: lineHeight,
                padding: const EdgeInsets.fromLTRB(28, 18, 20, 30),
                child: Text(
                  note.text,
                  style: body,
                  strutStyle: StrutStyle(
                    fontFamily: body.fontFamily,
                    fontSize: 17,
                    height: lineHeight / 17,
                    forceStrutHeight: true,
                  ),
                ),
              ),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _Disappeared(),
          ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: InkButton(
            label: 'Close',
            outlined: true,
            onPressed: () {
              _controller.discardNote(widget.noteId);
              context.nav.pop();
            },
          ),
        ),
      ],
    );
  }
}

/// Seconds left, refreshed independently of provider updates.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.note});
  final PeopleNote note;
  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (widget.note.remaining.inMilliseconds / 1000).ceil();
    return Semantics(
      label: 'Reading time remaining',
      value: '$seconds seconds',
      child: PeopleChip(
        icon: const FlameIcon(size: 15),
        color: seconds <= 5
            ? PeoplePalette.of(context).wax
            : const Color(0xFFD0662A),
        label: '${seconds}s',
      ),
    );
  }
}

class _Disappeared extends StatelessWidget {
  const _Disappeared();
  @override
  Widget build(BuildContext context) {
    final palette = PeoplePalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            CustomPaint(
              size: const Size(150, 70),
              painter: _AshPilePainter(palette.ink),
            ),
            const SizedBox(height: 18),
            Text(
              'This note has disappeared.',
              textAlign: TextAlign.center,
              style: peopleHand(context, size: 28),
            ),
            const SizedBox(height: 6),
            Text(
              'Only ashes, and whatever you remember.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _AshPilePainter extends CustomPainter {
  const _AshPilePainter(this.ink);
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(3);
    final base = size.height * .9;
    // A low mound of flakes, darker at the core.
    for (var i = 0; i < 70; i++) {
      final spread = random.nextDouble() * 2 - 1;
      final x = size.width / 2 + spread * size.width * .45;
      final height = (1 - spread * spread) * size.height * .45;
      final y = base - random.nextDouble() * height;
      final s = 2 + random.nextDouble() * 4;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(random.nextDouble() * pi);
      canvas.drawPath(
        Path()
          ..moveTo(-s, -s * .3)
          ..lineTo(s * .4, -s * .6)
          ..lineTo(s, s * .2)
          ..lineTo(-s * .3, s * .5)
          ..close(),
        Paint()
          ..color = Color.lerp(
            const Color(0xFF2A211C),
            const Color(0xFF8A817A),
            random.nextDouble(),
          )!.withValues(alpha: .55 + random.nextDouble() * .35),
      );
      canvas.restore();
    }
    // A last thread of smoke.
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .52, base - size.height * .4)
        ..cubicTo(
          size.width * .42,
          size.height * .3,
          size.width * .64,
          size.height * .2,
          size.width * .54,
          0,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = ink.withValues(alpha: .18),
    );
  }

  @override
  bool shouldRepaint(_AshPilePainter old) => old.ink != ink;
}

class PeopleHost extends ConsumerWidget {
  const PeopleHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(peopleControllerProvider, (previous, next) {
      final navContext = navigatorKey.currentContext;
      if (navContext == null) return;
      final messenger = ScaffoldMessenger.maybeOf(navContext);
      if (!next.foreground) {
        messenger?.hideCurrentSnackBar();
        return;
      }
      final oldIds = previous?.notes.map((n) => n.id).toSet() ?? <int>{};
      final incoming = next.notes
          .where((n) => !oldIds.contains(n.id))
          .firstOrNull;
      if (incoming == null) return;
      final name = next.person(incoming.friendKey)?.name ?? 'a friend';
      messenger?.showSnackBar(
        SnackBar(
          content: Text('A note from $name'),
          action: SnackBarAction(
            label: 'Open Friends',
            onPressed: () {
              final context = navigatorKey.currentContext;
              if (context != null) context.nav.push(const PeoplePage());
            },
          ),
        ),
      );
    });
    return child;
  }
}
