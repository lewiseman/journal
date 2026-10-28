import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:journal/common.dart';
import 'package:journal/modules/more/views/widgets/more_index_entry.dart';
import 'package:journal/modules/more/views/widgets/more_material.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';

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

  void _expandAccount() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncAccount = ref.watch(syncAccountProvider);
    final connection = ref.watch(companionControllerProvider);
    return MoreSurface(
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: MoreSurface.contentWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minHeight = SyncAccountCard.compactHeight(context) + 24;
                final maxHeight =
                    SyncAccountCard.expandedHeight(
                      context,
                      isSignedIn: syncAccount != null,
                    ) +
                    44;
                return CustomScrollView(
                  key: const PageStorageKey('more-scroll'),
                  controller: _scroll,
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _AccountHeader(
                        minHeight: minHeight,
                        maxHeight: maxHeight,
                        onExpand: _expandAccount,
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
                          padding: const EdgeInsets.fromLTRB(28, 4, 28, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              MoreIndexEntry(
                                title: 'Appearance',
                                description: 'Colors, theme and fonts',
                                artwork: MoreEntryArtwork.swatches,
                                onTap: () =>
                                    context.nav.push(const AppearancePage()),
                              ),
                              MoreIndexEntry(
                                title: 'Local AI computer',
                                status: companionPhaseLabel(connection.phase),
                                connected:
                                    connection.phase ==
                                    CompanionPhase.connected,
                                artwork: MoreEntryArtwork.computer,
                                onTap: () =>
                                    context.nav.push(const CompanionPage()),
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
      ),
    );
  }
}

class _AccountHeader extends SliverPersistentHeaderDelegate {
  const _AccountHeader({
    required this.minHeight,
    required this.maxHeight,
    required this.onExpand,
  });

  final double minHeight, maxHeight;
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
    return MoreSurface(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          28,
          lerpDouble(28, 12, progress)!,
          28,
          lerpDouble(16, 12, progress)!,
        ),
        child: SyncAccountCard(collapseProgress: progress, onExpand: onExpand),
      ),
    );
  }

  @override
  bool shouldRebuild(_AccountHeader oldDelegate) =>
      minHeight != oldDelegate.minHeight ||
      maxHeight != oldDelegate.maxHeight ||
      onExpand != oldDelegate.onExpand;
}
