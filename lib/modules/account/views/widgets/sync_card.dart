import 'package:journal/common.dart';

import 'dart:ui' show lerpDouble;

import 'package:sync_wise/sync_wise.dart';

class SyncAccountCard extends ConsumerWidget {
  const new({
    super.key,
    required this.collapseProgress,
    required this.onExpand,
  });

  final double collapseProgress;
  final VoidCallback onExpand;

  static double compactHeight(BuildContext context) =>
      48 + MediaQuery.textScalerOf(context).scale(38);

  static double _expandedIdentityHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return 88 + 16 + scaler.scale(22) * 1.2 + 4 + scaler.scale(12) * 1.3;
  }

  static double expandedHeight(
    BuildContext context, {
    required bool isSignedIn,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    // Text stays on one line, so height is independent of sync state and width.
    final statusHeight =
        28 +
        (scaler.scale(13) * 1.35 + 5 + scaler.scale(12) * 1.45).clamp(
          24.0,
          double.infinity,
        );
    // Reserve space for the Google mark, the tallest button content.
    final buttonHeight = (28 + scaler.scale(18) * 1.35).clamp(
      48.0,
      double.infinity,
    );
    final captionHeight = scaler.scale(10) * 1.3;
    final height =
        (24 +
                _expandedIdentityHeight(context) +
                20 +
                statusHeight +
                18 +
                buttonHeight +
                12 +
                captionHeight +
                28)
            .clamp(368.0, double.infinity);
    // Remove the hidden button and its spacing after applying the minimum.
    return isSignedIn ? height - 18 - buttonHeight : height;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = CacheStorage.instance.get(userNameKey);
    final syncAccountAsync = ref.watch(authStateProvider);
    final syncState = ref.watch(syncEngineProvider);
    final syncBackend = ref.watch(syncBackendProvider);
    final syncAccount = syncAccountAsync.value;
    final isSignedIn = syncAccount != null;
    final colors = context.colors;
    final t = collapseProgress.clamp(0.0, 1.0);
    final fade = (1 - t * 2).clamp(0.0, 1.0);
    const identityTop = 24.0;
    final identityHeight = _expandedIdentityHeight(context);
    final radius = BorderRadius.circular(lerpDouble(30, 20, t)!);
    final compact = t >= .6;
    final error = syncState.status == EngineSyncState.error;
    final statusColor = error ? colors.error : colors.primary;
    return Material(
      key: const ValueKey('sync-account-card'),
      color: colors.surface,
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: colors.glow(lerpDouble(.22, .12, t)!),
              blurRadius: lerpDouble(30, 14, t)!,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    colors.primaryContainer,
                    colors.surfaceContainerLow,
                    t * .7,
                  )!,
                  colors.surfaceContainerLow,
                  Color.alphaBlend(
                    colors.primary.withValues(alpha: .05),
                    colors.surface,
                  ),
                ],
              ),
              borderRadius: radius,
              border: Border.all(color: colors.primary.withValues(alpha: .14)),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CloudOrbitPainter(
                        colors.primary,
                        (1 - t) * .75,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: lerpDouble(identityTop, 16, t),
                  left: lerpDouble(24, 16, t),
                  right: lerpDouble(24, 16, t),
                  child: Semantics(
                    button: compact,
                    onTap: compact ? onExpand : null,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: compact ? onExpand : null,
                      child: _AccountIdentity(
                        syncAccount: syncAccount,
                        title: name ?? 'Your account',
                        syncStatus: syncState.status.statusLabel,
                        collapseProgress: t,
                        statusColor: statusColor,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: identityTop + identityHeight + 20,
                  left: 24,
                  right: 24,
                  bottom: 20,
                  child: IgnorePointer(
                    ignoring: t > .15,
                    child: ExcludeSemantics(
                      excluding: t > .15,
                      child: Opacity(
                        opacity: fade,
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          maxHeight: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colors.surface.withValues(alpha: .65),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: colors.primary.withValues(
                                      alpha: .07,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: syncState.isSyncing
                                          ? SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                value:
                                                    MediaQuery.disableAnimationsOf(
                                                      context,
                                                    )
                                                    ? .7
                                                    : null,
                                                color: statusColor,
                                              ),
                                            )
                                          : Icon(
                                              syncState.status.icon,
                                              color: statusColor,
                                              size: 22,
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Semantics(
                                            liveRegion: true,
                                            child: Text(
                                              syncState.statusLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: colors.primary,
                                                fontSize: 13,
                                                height: 1.35,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            syncState.descriptionFor(
                                              syncBackend,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: colors.onSurfaceVariant,
                                              fontSize: 12,
                                              height: 1.45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isSignedIn) ...[
                                const SizedBox(height: 18),
                                FilledButton(
                                  key: const ValueKey('sync-card-action'),
                                  onPressed: () async {
                                    final user = await ref
                                        .read(syncAuthProvider)
                                        .signIn();
                                    if (user != null && context.mounted) {
                                      await ref
                                          .read(syncEngineProvider.notifier)
                                          .syncNow(manual: true);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ref
                                                          .read(
                                                            syncEngineProvider,
                                                          )
                                                          .lastError ==
                                                      null
                                                  ? 'Connected as ${user.email}.'
                                                  : 'Connected, but backup is incomplete. See the sync error below.',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'G',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          'Connect  Account',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.35,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 17,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                'Your notes. Your account.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 10,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudOrbitPainter extends CustomPainter {
  const _CloudOrbitPainter(this.color, this.opacity);
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 8, 65);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final radius in [78.0, 112.0, 148.0]) {
      canvas.drawCircle(
        center,
        radius,
        paint..color = color.withValues(alpha: .08 * opacity),
      );
    }
    canvas.drawCircle(
      center + const Offset(-78, 0),
      3,
      Paint()..color = color.withValues(alpha: .24 * opacity),
    );
    canvas.drawCircle(
      center + const Offset(-78, 80),
      4,
      Paint()..color = color.withValues(alpha: .13 * opacity),
    );
  }

  @override
  bool shouldRepaint(_CloudOrbitPainter oldDelegate) =>
      color != oldDelegate.color || opacity != oldDelegate.opacity;
}

class _AccountIdentity extends StatelessWidget {
  const _AccountIdentity({
    required this.title,
    required this.collapseProgress,
    required this.statusColor,
    required this.syncAccount,
    required this.syncStatus,
  });

  final String title;
  final double collapseProgress;
  final Color statusColor;
  final SyncAccount? syncAccount;
  final String syncStatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = collapseProgress;
    final compact = t >= .6;
    // Make room beside the avatar before lifting the name into the compact row.
    final horizontal = Curves.easeInOut.transform((t / .3).clamp(0.0, 1.0));
    final vertical = ((t - .3) / .7).clamp(0.0, 1.0);
    final avatarSize = lerpDouble(88, 42, t)!;
    final compactHeight = SyncAccountCard.compactHeight(context) - 32;
    final alignment = AlignmentDirectional.lerp(
      AlignmentDirectional.center,
      AlignmentDirectional.centerStart,
      horizontal,
    )!;

    return SizedBox(
      height: lerpDouble(
        SyncAccountCard._expandedIdentityHeight(context),
        compactHeight,
        vertical,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            PositionedDirectional(
              top: lerpDouble(0, (compactHeight - 42) / 2, vertical),
              start: lerpDouble(
                (constraints.maxWidth - avatarSize) / 2,
                0,
                horizontal,
              ),
              child: _AccountAvatar(
                size: avatarSize,
                name: title,
                avatar: syncAccount?.photoUrl ?? '',
              ),
            ),
            PositionedDirectional(
              top: lerpDouble(104, 0, vertical),
              bottom: 0,
              start: lerpDouble(0, avatarSize + 12, horizontal),
              end: lerpDouble(0, 28, horizontal),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: alignment,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: lerpDouble(22, 16, t),
                        height: 1.2,
                        letterSpacing: -.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: alignment,
                    child: Text(
                      compact
                          ? syncStatus
                          : (syncAccount?.email ?? 'A little peace of mind.'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: compact ? statusColor : colors.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (compact)
              PositionedDirectional(
                top: 0,
                bottom: 0,
                end: 0,
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: ((t - .6) / .4).clamp(0.0, 1.0),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: colors.primary,
                      size: 22,
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

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.size,
    required this.name,
    required this.avatar,
  });
  final double size;
  final String name;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    final initials = name.isEmpty
        ? ''
        : name
              .split(RegExp(r'\s+'))
              .take(2)
              .map((part) => part.characters.first)
              .join()
              .toUpperCase();
    final fallback = Center(
      child: initials.isNotEmpty
          ? Text(
              initials,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: context.colors.primary,
                fontSize: size * .32,
                fontWeight: FontWeight.w600,
              ),
            )
          : Icon(
              Icons.cloud_outlined,
              color: context.colors.primary,
              size: size * .46,
            ),
    );
    return Container(
      key: const ValueKey('sync-avatar'),
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colors.surface,
        border: Border.all(
          color: context.colors.primary.withValues(alpha: .18),
        ),
        boxShadow: [
          BoxShadow(
            color: context.colors.glow(.16),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: ColoredBox(
          color: context.colors.primaryContainer,
          child: fallback,
        ),
      ),
    );
  }
}
