import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:journal/common.dart';
import 'package:journal/modules/account/views/widgets/sync_account_sheet.dart';
import 'package:journal/modules/more/views/widgets/more_material.dart';
import 'package:sync_wise/sync_wise.dart';

/// An ownership bookplate which folds down to a pinned account strip.
class SyncAccountCard extends ConsumerWidget {
  const new({
    super.key,
    required this.collapseProgress,
    required this.onExpand,
  });

  final double collapseProgress;
  final VoidCallback onExpand;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      final account = await ref.read(syncAuthProvider).signIn();
      if (account == null || !context.mounted) return;
      await ref.read(syncEngineProvider.notifier).syncNow(manual: true);
      if (!context.mounted) return;
      final error = ref.read(syncEngineProvider).lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Connected as ${account.email}.')),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  static double _identityHeight(BuildContext context, {bool compact = false}) {
    final scaler = MediaQuery.textScalerOf(context);
    return math.max(
      compact ? 34 : 48,
      (scaler.scale(compact ? 16 : 24) * 1.2).ceilToDouble() +
          4 +
          (scaler.scale(compact ? 11 : 12) * 1.4).ceilToDouble() +
          2,
    );
  }

  static double compactHeight(BuildContext context) =>
      28 + _identityHeight(context, compact: true);

  static const _identityTop = 20.0;

  static double expandedHeight(
    BuildContext context, {
    required bool isSignedIn,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    return _identityTop +
        _identityHeight(context) +
        16 +
        25 +
        scaler.scale(13) * 1.35 +
        scaler.scale(12) * 1.45 +
        (isSignedIn ? 0 : 14 + math.max(48, 24 + scaler.scale(13) * 1.35)) +
        18;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = CacheStorage.instance.get(userNameKey)?.toString().trim();
    final title = name == null || name.isEmpty ? 'Your journal' : name;
    final syncAccount = ref.watch(syncAccountProvider);
    final engineState = ref.watch(syncEngineProvider);
    final syncBackend = ref.watch(syncBackendProvider);
    final isSignedIn = syncAccount != null;
    final syncState = isSignedIn
        ? engineState
        : const SyncEngineState(status: EngineSyncState.unauthenticated);
    final palette = MorePalette.of(context);
    final t = collapseProgress.clamp(0.0, 1.0);
    final compact = t >= .6;
    final fade = (1 - t * 3).clamp(0.0, 1.0);
    final statusColor = syncState.status == EngineSyncState.error
        ? context.colors.error
        : palette.accent;
    final identityHeight = _identityHeight(context);
    final initials = title
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    const radius = BorderRadius.all(Radius.circular(3));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paper,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: .06),
            offset: const Offset(0, 3),
            blurRadius: 4,
          ),
        ],
      ),
      child: Material(
        key: const ValueKey('sync-account-card'),
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: palette.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              top: lerpDouble(_identityTop, 14, t),
              left: 20,
              right: 20,
              child: Semantics(
                button: compact,
                onTap: compact ? onExpand : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: compact ? onExpand : null,
                  child: SizedBox(
                    height: lerpDouble(
                      identityHeight,
                      _identityHeight(context, compact: true),
                      t,
                    ),
                    child: Row(
                      children: [
                        Container(
                          key: const ValueKey('sync-avatar'),
                          width: lerpDouble(48, 32, t),
                          height: lerpDouble(48, 32, t),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.cloth,
                            border: Border.all(color: palette.rule),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            initials,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              color: palette.accent,
                              fontSize: lerpDouble(19, 13, t),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.ink,
                                  fontSize: lerpDouble(24, 16, t),
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -.5,
                                ),
                              ),
                              if (isSignedIn || compact) ...[
                                const SizedBox(height: 4),
                                Text(
                                  compact
                                      ? syncState.status.statusLabel
                                      : syncAccount!.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: compact
                                        ? statusColor
                                        : palette.muted,
                                    fontSize: lerpDouble(12, 11, t),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (compact)
                          Icon(
                            Icons.expand_more_rounded,
                            color: palette.accent,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: _identityTop + identityHeight + 16,
              left: 20,
              right: 20,
              child: IgnorePointer(
                ignoring: t > .15,
                child: ExcludeSemantics(
                  excluding: t > .15,
                  child: Opacity(
                    opacity: fade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          key: const ValueKey('sync-card-status'),
                          onTap: isSignedIn
                              ? () => context.nav.sheet<void>(
                                  (_) => const SyncAccountSheet(),
                                )
                              : null,
                          child: Ink(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: palette.rule),
                              ),
                            ),
                            child: Row(
                              children: [
                                if (syncState.isSyncing)
                                  SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: statusColor,
                                      value:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? .7
                                          : null,
                                    ),
                                  )
                                else
                                  Icon(
                                    syncState.status.icon,
                                    color: statusColor,
                                    size: 20,
                                  ),
                                const SizedBox(width: 10),
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
                                            color: statusColor,
                                            fontSize: 13,
                                            height: 1.35,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Tooltip(
                                        message: syncState.descriptionFor(
                                          syncBackend,
                                        ),
                                        child: Text(
                                          syncState.descriptionFor(syncBackend),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: palette.muted,
                                            fontSize: 12,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSignedIn) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: palette.accent,
                                    size: 17,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (!isSignedIn) ...[
                          const SizedBox(height: 14),
                          FilledButton(
                            key: const ValueKey('sync-card-action'),
                            onPressed: engineState.isSyncing
                                ? null
                                : () => _connect(context, ref),
                            style: FilledButton.styleFrom(
                              backgroundColor: palette.accent,
                              minimumSize: const Size.fromHeight(48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'G',
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Connect Account',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 17,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
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
