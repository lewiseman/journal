import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/utils/navigation_helper.dart';

import 'people_controller.dart';
import 'people_models.dart';
import 'widgets/burning_paper.dart';
import 'widgets/friend_avatar.dart';
import 'widgets/people_paper.dart';
import 'widgets/people_header_artwork.dart';
import 'widgets/note_arrival_banner.dart';
import 'widgets/reading_note_sheet.dart';

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
    final colors = Theme.of(context).colorScheme;
    if (state.supported && (state.loading || state.busy)) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: LinearProgressIndicator(semanticsLabel: 'Connecting'),
      );
    }
    final message = !state.supported
        ? 'Friends works on Android phones for now.'
        : state.message;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    state.supported
                        ? Icons.wifi_off_rounded
                        : Icons.phone_android_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(message)),
                ],
              ),
              if (state.supported)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
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
      ),
    );
  }
}

class PeoplePage extends ConsumerWidget {
  const PeoplePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peopleControllerProvider);
    final unopened = state.notes.where((n) => !n.opened).toList();
    final canAdd = state.supported && !state.loading;
    return PeopleTabbedScaffold(
      title: 'People',
      headerArtwork: const PeopleHeaderArtwork(),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton.filledTonal(
            key: const ValueKey('people-add-friend'),
            tooltip: 'Add friend',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: canAdd
                ? () => context.nav.push(const AddFriendPage())
                : null,
          ),
        ),
      ],
      tabs: [
        Tab(
          child: _TabLabel(
            'Friends',
            count: state.friends.length,
            icon: Icons.people_outline_rounded,
          ),
        ),
        Tab(
          child: _TabLabel(
            'Notes',
            count: unopened.length,
            icon: Icons.mail_outline_rounded,
          ),
        ),
      ],
      views: [
        PeopleTabView(
          key: const ValueKey('people-friends-view'),
          slivers: [
            const SliverToBoxAdapter(child: _Status()),
            if (state.candidates.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _KnockCard(
                    name: state.candidates.first.name,
                    friendKey: state.candidates.first.key,
                    onTap: () => context.nav.push(const AddFriendPage()),
                  ),
                ),
              ),
            if (state.friends.isEmpty)
              SliverToBoxAdapter(
                child: _PeopleEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'Your people, right here',
                  message: 'Add a friend with an invitation or QR code to share disappearing notes.',
                  action: InkButton(
                    label: 'Add friend',
                    icon: Icons.person_add_alt_1_rounded,
                    expand: false,
                    onPressed: canAdd
                        ? () => context.nav.push(const AddFriendPage())
                        : null,
                  ),
                ),
              )
            else
              SliverList.separated(
                itemCount: state.friends.length,
                separatorBuilder: (_, _) => const Padding(
                  padding: EdgeInsets.only(left: 72),
                  child: Divider(height: 1),
                ),
                itemBuilder: (context, index) {
                  final person = state.friends[index];
                  return _FriendTile(
                    key: ValueKey('people-friend-${person.key}'),
                    person: person,
                    unopened: unopened
                        .where((n) => n.friendKey == person.key)
                        .length,
                  );
                },
              ),
          ],
        ),
        PeopleTabView(
          key: const ValueKey('people-notes-view'),
          slivers: [
            const SliverToBoxAdapter(child: _Status()),
            if (unopened.isEmpty)
              const SliverToBoxAdapter(
                child: _PeopleEmptyState(
                  icon: Icons.mark_email_unread_outlined,
                  title: 'No notes waiting',
                  message: 'Keep both apps open to exchange notes. Each note opens once and disappears after reading.',
                ),
              )
            else
              SliverList.separated(
                itemCount: unopened.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) => _NoteTile(
                  key: ValueKey('people-note-${unopened[index].id}'),
                  id: unopened[index].id,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, {required this.count, this.icon});
  final String label;
  final int count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null && MediaQuery.textScalerOf(context).scale(14) <= 20) ...[
        Icon(icon, size: 18),
        const SizedBox(width: 7),
      ],
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      if (count > 0) ...[
        const SizedBox(width: 8),
        Badge.count(
          count: count,
          backgroundColor: Theme.of(context).colorScheme.primary,
          textColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ],
    ],
  );
}

class _PeopleEmptyState extends StatelessWidget {
  const _PeopleEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 32, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({super.key, required this.person, required this.unopened});
  final Person person;
  final int unopened;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    leading: FriendAvatar(
      friendKey: person.key,
      name: person.name,
      size: 52,
      hero: true,
    ),
    title: Text(person.name, style: peopleTitle(context, size: 17)),
    subtitle: unopened == 0
        ? null
        : Text(
            unopened == 1 ? '1 note waiting' : '$unopened notes waiting',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
    trailing: Icon(
      Icons.chevron_right_rounded,
      color: PeoplePalette.of(context).muted,
    ),
    onTap: () => context.nav.push(FriendDetailsPage(friendKey: person.key)),
  );
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
  Widget build(BuildContext context) => Card.filled(
    margin: EdgeInsets.zero,
    child: ListTile(
      contentPadding: const EdgeInsets.all(12),
      leading: FriendAvatar(friendKey: friendKey, name: name, size: 44),
      title: Text(name),
      subtitle: const Text('Friend request'),
      trailing: const Icon(Icons.arrow_forward_rounded),
      onTap: onTap,
    ),
  );
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
    final invite = state.invite;
    final canReceive =
        state.supported && !state.busy && state.candidates.isEmpty;
    return PeopleTabbedScaffold(
      title: 'Add friend',
      tabs: [
        Tab(child: _TabLabel('Invite', count: state.candidates.length)),
        const Tab(text: 'Accept'),
      ],
      views: [
        PeopleTabView(
          key: const ValueKey('people-invite-view'),
          slivers: [
            const SliverToBoxAdapter(child: _Status()),
            for (final person in state.candidates)
              SliverToBoxAdapter(
                child: Card.filled(
                  margin: const EdgeInsets.only(bottom: 20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final avatar = FriendAvatar(
                              friendKey: person.key,
                              name: person.name,
                              size: 52,
                            );
                            final identity = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  person.name,
                                  style: peopleTitle(context, size: 20),
                                ),
                                const Text('Friend request'),
                              ],
                            );
                            if (constraints.maxWidth < 280 ||
                                MediaQuery.textScalerOf(context).scale(20) >
                                    28) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  avatar,
                                  const SizedBox(height: 12),
                                  identity,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                avatar,
                                const SizedBox(width: 14),
                                Expanded(child: identity),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            InkButton(
                              label: 'Confirm friend',
                              expand: false,
                              onPressed: state.busy
                                  ? null
                                  : () => _action(
                                      context,
                                      () => controller.confirm(person, true),
                                    ),
                            ),
                            TextButton(
                              onPressed: state.busy
                                  ? null
                                  : () => _action(
                                      context,
                                      () => controller.confirm(person, false),
                                    ),
                              child: const Text('Decline'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (state.candidates.isEmpty)
              SliverToBoxAdapter(
                child: invite == null || invite.expired
                    ? _PeopleEmptyState(
                        icon: Icons.qr_code_rounded,
                        title: 'Make a new connection',
                        message: 'Show your QR code or copy an invitation. Keep Journal open while your friend connects.',
                        action: InkButton(
                          label: 'Create invitation',
                          icon: Icons.qr_code_rounded,
                          expand: false,
                          onPressed: canReceive
                              ? () => _action(context, controller.createInvite)
                              : null,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: _InviteTicket(
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
                          onCancel: () =>
                              _action(context, controller.cancelInvite),
                        ),
                      ),
              ),
          ],
        ),
        PeopleTabView(
          key: const ValueKey('people-accept-view'),
          slivers: [
            const SliverToBoxAdapter(child: _Status()),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkButton(
                    label: 'Scan invitation',
                    icon: Icons.qr_code_scanner_rounded,
                    onPressed: canReceive
                        ? () async {
                            final raw = await context.nav.push<String>(
                              const PeopleScannerPage(),
                            );
                            if (raw != null && mounted) await _accept(raw);
                          }
                        : null,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Invitation code',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _paste,
                    maxLength: 2048,
                    minLines: 3,
                    maxLines: 5,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Paste invitation',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkButton(
                    label: 'Accept pasted invitation',
                    outlined: true,
                    onPressed: canReceive ? () => _accept(_paste.text) : null,
                  ),
                ],
              ),
            ),
          ],
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
          style: peopleTitle(context, size: 28, color: Colors.white),
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
              style: peopleTitle(context, size: 24, color: Colors.white),
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

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
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
        await ref.read(peopleControllerProvider.notifier).remove(person);
        if (context.mounted) context.nav.pop();
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peopleControllerProvider);
    final person = state.person(friendKey);
    final notes = state.notes
        .where((n) => n.friendKey == friendKey && !n.opened)
        .toList();
    return PeopleScaffold(
      title: 'Friend',
      actions: [
        if (person != null)
          PopupMenuButton<String>(
            tooltip: 'Friend options',
            onSelected: (_) => _remove(context, ref, person),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'remove',
                child: Text(
                  'Remove friend',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
      ],
      children: [
        const _Status(),
        if (person == null)
          const _PeopleEmptyState(
            icon: Icons.person_off_outlined,
            title: 'Friend removed',
            message: 'Add them again with a new invitation to reconnect.',
          )
        else ...[
          const SizedBox(height: 16),
          Center(
            child: FriendAvatar(
              friendKey: person.key,
              name: person.name,
              size: 96,
              hero: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            person.name,
            textAlign: TextAlign.center,
            style: peopleTitle(context, size: 28),
          ),
          const SizedBox(height: 28),
          InkButton(
            key: const ValueKey('people-write-note'),
            label: 'Write a note',
            icon: Icons.edit_outlined,
            onPressed: () =>
                context.nav.push(WritePeopleNotePage(friendKey: friendKey)),
          ),
          const SizedBox(height: 32),
          PeopleHeading(
            'Notes',
            trailing: notes.isEmpty ? null : Text('${notes.length} waiting'),
          ),
          if (notes.isEmpty)
            const _PeopleEmptyState(
              icon: Icons.mark_email_unread_outlined,
              title: 'Nothing waiting, yet',
              message: 'Keep both apps open to exchange notes. Each note disappears after reading.',
            )
          else
            for (final note in notes) ...[
              _NoteTile(id: note.id),
              const SizedBox(height: 12),
            ],
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
    final body = peopleBody(context, size: 17);
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
                  style: peopleTitle(context, size: 20),
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
                  '${peopleReadingTime(_text.text).inSeconds} seconds to read',
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
          if (_text.text.isEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Keep both apps open to send. Notes disappear after reading and aren’t saved.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.muted),
            ),
          ],
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
          bytes > 8192
              ? 'Note is too large · $words / 500 words'
              : '$words / 500 words',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: over ? palette.wax : palette.muted),
        ),
      ],
    );
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peopleControllerProvider);
    final note = state.note(id);
    if (note == null || note.opened) return const SizedBox.shrink();
    final name = state.person(note.friendKey)?.name ?? 'a friend';
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: FriendAvatar(friendKey: note.friendKey, name: name, size: 44),
        title: Text('From $name', style: peopleTitle(context, size: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              const FlameIcon(size: 13),
              const SizedBox(width: 6),
              Flexible(child: Text('${note.duration.inSeconds}s · Opens once')),
            ],
          ),
        ),
        trailing: const Icon(Icons.arrow_outward_rounded, size: 20),
        onTap: () {
          ref.read(peopleControllerProvider.notifier).openNote(id);
          context.nav.push(ReadPeopleNotePage(noteId: id));
        },
      ),
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
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 650;
    final wide = size.width > size.height * 1.3;
    final verticalPadding = compact ? 0.0 : 12.0;
    final name = visible
        ? state.person(note.friendKey)?.name ?? 'a friend'
        : null;
    final reader = LayoutBuilder(
      builder: (context, viewport) => Scrollbar(
        child: SingleChildScrollView(
          key: const ValueKey('people-reading-scroll'),
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: max(0, viewport.maxHeight - verticalPadding * 2),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: visible
                    ? LayoutBuilder(
                        builder: (context, paper) => BurningPaper(
                          seed: note.id,
                          inset: 28,
                          progress: () =>
                              1 -
                              note.remaining.inMilliseconds /
                                  note.duration.inMilliseconds,
                          child: Padding(
                            // Keep the paper and its shadow inside the burn mask.
                            padding: const EdgeInsets.all(28),
                            child: ReadingNoteSheet(
                              text: note.text,
                              minHeight: max(
                                280,
                                min(
                                  420,
                                  min(
                                    (paper.maxWidth - 56) * 1.08,
                                    viewport.maxHeight -
                                        56 -
                                        verticalPadding * 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: _Disappeared(),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    final countdown = visible
        ? Padding(
            key: const ValueKey('people-reading-countdown'),
            padding: EdgeInsets.only(
              top: compact ? 4 : 8,
              bottom: compact ? 0 : 4,
            ),
            child: Center(child: _Countdown(note: note)),
          )
        : const SizedBox.shrink();
    final hint = Text(
      'Disappears when closed',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
    );
    final close = Semantics(
      hint: compact && !wide && visible ? 'Closing discards this note' : null,
      child: InkButton(
        key: const ValueKey('people-close-note'),
        label: 'Close',
        icon: Icons.close_rounded,
        outlined: true,
        onPressed: () {
          _controller.discardNote(widget.noteId);
          context.nav.pop();
        },
      ),
    );
    return QvacAssistantPage(
      enabled: false,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          title: visible
              ? Row(
                  children: [
                    FriendAvatar(
                      friendKey: note.friendKey,
                      name: name!,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'From $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                )
              : const Text('Note disappeared'),
        ),
        body: SafeArea(
          top: false,
          child: wide
              ? Row(
                  children: [
                    Expanded(child: reader),
                    SizedBox(
                      width: 200,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 28, 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (visible) ...[
                              countdown,
                              const SizedBox(height: 20),
                              hint,
                              const SizedBox(height: 16),
                            ],
                            close,
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    if (visible) countdown,
                    Expanded(child: reader),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            28,
                            compact ? 4 : 8,
                            28,
                            compact ? 12 : 16,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (visible && !compact) ...[
                                hint,
                                const SizedBox(height: 12),
                              ],
                              close,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
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
              style: peopleTitle(context, size: 22),
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
        messenger?.clearSnackBars();
        return;
      }
      final oldIds = previous?.notes.map((n) => n.id).toSet() ?? <int>{};
      final incoming = next.notes
          .where((n) => !oldIds.contains(n.id))
          .firstOrNull;
      if (incoming == null) return;
      if (messenger == null) return;
      final name = next.person(incoming.friendKey)?.name ?? 'a friend';
      // Keep arrivals current instead of replaying a backlog of old notices.
      messenger.clearSnackBars();
      final reduced = MediaQuery.disableAnimationsOf(navContext);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.none,
          duration: const Duration(seconds: 8),
          persist: MediaQuery.accessibleNavigationOf(navContext),
          content: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: NoteArrivalBanner(
                key: ValueKey('people-arrival-${incoming.id}'),
                name: name,
                friendKey: incoming.friendKey,
                onDismiss: () => messenger.hideCurrentSnackBar(),
                onOpen: () {
                  messenger.hideCurrentSnackBar();
                  final context = navigatorKey.currentContext;
                  if (context != null) context.nav.push(const PeoplePage());
                },
              ),
            ),
          ),
        ),
        snackBarAnimationStyle: reduced
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
                duration: Duration(milliseconds: 400),
                reverseDuration: Duration(milliseconds: 240),
              ),
      );
    });
    return child;
  }
}
