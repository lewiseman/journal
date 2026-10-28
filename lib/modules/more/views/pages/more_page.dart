import 'package:journal/common.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';

import 'dart:ui' show lerpDouble;
import 'dart:math' as math;

class MorePage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncAccount = ref.watch(syncAccountProvider);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minHeight = SyncAccountCard.compactHeight(context) + 28;
              final maxHeight =
                  SyncAccountCard.expandedHeight(
                    context,
                    isSignedIn: syncAccount != null,
                  ) +
                  28;
              return CustomScrollView(
                key: const PageStorageKey('more-scroll'),
                controller: _scroll,
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SyncHeader(
                      minHeight: minHeight,
                      maxHeight: maxHeight,
                      onExpand: () {
                        _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 380),
                          curve: Curves.easeOutCubic,
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(
                          240,
                          constraints.maxHeight - minHeight,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Make it yours',
                              style: TextStyle(
                                color: context.colors.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Small details. A space that feels like you.',
                              style: TextStyle(
                                color: context.colors.onSurfaceVariant,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Material(
                              color: context.colors.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: context.colors.outlineVariant
                                      .withValues(alpha: .5),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: context.colors.primaryContainer,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    color: context.colors.primary,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  'Settings',
                                  style: TextStyle(
                                    color: context.colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  'Colors, appearance and fonts',
                                  style: TextStyle(
                                    color: context.colors.onSurfaceVariant,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: context.colors.primary,
                                ),
                                onTap: () => context.nav.push(SettingsPage()),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Material(
                              color: context.colors.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: context.colors.outlineVariant
                                      .withValues(alpha: .5),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: const CompanionNavigationTile(),
                            ),
                            const SizedBox(height: 44),
                            Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.spa_outlined,
                                    size: 22,
                                    color: context.colors.primary.withValues(
                                      alpha: .5,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'A quiet space for a busy mind.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: context.colors.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SyncHeader extends SliverPersistentHeaderDelegate {
  const _SyncHeader({
    required this.minHeight,
    required this.maxHeight,
    required this.onExpand,
  });

  final double minHeight;
  final double maxHeight;

  // final VoidCallback onAction;
  final VoidCallback onExpand;

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentGeometry.topCenter,
          end: AlignmentGeometry.bottomCenter,
          colors: [
            context.colors.surface,
            context.colors.surface.withValues(alpha: .2),
          ],
        ),
      ),

      child: Padding(
        padding: EdgeInsets.fromLTRB(
          lerpDouble(24, 12, progress)!,
          12,
          lerpDouble(24, 12, progress)!,
          16,
        ),
        child: SyncAccountCard(collapseProgress: progress, onExpand: onExpand),
      ),
    );
  }

  @override
  bool shouldRebuild(_SyncHeader oldDelegate) =>
      minHeight != oldDelegate.minHeight ||
      maxHeight != oldDelegate.maxHeight ||
      onExpand != oldDelegate.onExpand;
}
