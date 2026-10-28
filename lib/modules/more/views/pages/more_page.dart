import 'dart:math' as math;

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
    final palette = MorePalette.of(context);
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
                final openingHeight = _CoverOpening.height(
                  context,
                  constraints.maxWidth - 60,
                );
                final maxHeight =
                    openingHeight +
                    SyncAccountCard.expandedHeight(
                      context,
                      isSignedIn: syncAccount != null,
                    ) +
                    24;
                return CustomScrollView(
                  key: const PageStorageKey('more-scroll'),
                  controller: _scroll,
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _CoverHeader(
                        minHeight: minHeight,
                        maxHeight: maxHeight,
                        openingHeight: openingHeight,
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
                          padding: const EdgeInsets.fromLTRB(32, 12, 28, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text('THE DETAILS', style: palette.label),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Divider(
                                      color: palette.rule,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                              MoreIndexEntry(
                                number: '01',
                                title: 'Appearance',
                                description: 'Colors, theme and fonts',
                                artwork: MoreEntryArtwork.swatches,
                                onTap: () =>
                                    context.nav.push(const AppearancePage()),
                              ),
                              MoreIndexEntry(
                                number: '02',
                                title: 'Local AI computer',
                                description: 'Writing help from your computer.',
                                status: companionPhaseLabel(connection.phase),
                                connected:
                                    connection.phase ==
                                    CompanionPhase.connected,
                                artwork: MoreEntryArtwork.computer,
                                onTap: () =>
                                    context.nav.push(const CompanionPage()),
                              ),
                              const SizedBox(height: 18),
                              const Center(child: MoreOrnament(size: 22)),
                              const SizedBox(height: 10),
                              Text(
                                'A quiet space for a busy mind.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 11,
                                  height: 1.5,
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
      ),
    );
  }
}

class _CoverHeader extends SliverPersistentHeaderDelegate {
  const _CoverHeader({
    required this.minHeight,
    required this.maxHeight,
    required this.openingHeight,
    required this.onExpand,
  });

  final double minHeight, maxHeight, openingHeight;
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
    final titleFade = (1 - progress * 3).clamp(0.0, 1.0);
    return MoreSurface(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: 20 - shrinkOffset * .6,
            left: 32,
            right: 28,
            child: IgnorePointer(
              child: ExcludeSemantics(
                excluding: titleFade == 0,
                child: Opacity(
                  opacity: titleFade,
                  child: const _CoverOpening(),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12 + openingHeight * (1 - progress),
            bottom: 12,
            left: 32 - 8 * progress,
            right: 28 - 4 * progress,
            child: SyncAccountCard(
              collapseProgress: progress,
              onExpand: onExpand,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_CoverHeader oldDelegate) =>
      minHeight != oldDelegate.minHeight ||
      maxHeight != oldDelegate.maxHeight ||
      openingHeight != oldDelegate.openingHeight ||
      onExpand != oldDelegate.onExpand;
}

class _CoverOpening extends StatelessWidget {
  const _CoverOpening();

  static bool _largeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 20;

  static TextStyle _titleStyle(BuildContext context) => TextStyle(
    color: MorePalette.of(context).ink,
    // Display type grows more gently so the account remains in reach.
    fontSize:
        32 / (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1, 1.6),
    height: 1.15,
    fontWeight: FontWeight.w400,
    letterSpacing: -1.3,
  );

  static TextStyle _descriptionStyle(BuildContext context) => TextStyle(
    color: MorePalette.of(context).muted,
    fontSize: 12,
    height: 1.5,
  );

  static double height(BuildContext context, double width) {
    double measure(String text, TextStyle style, double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout(maxWidth: maxWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return 20 +
        math.max(
          24,
          measure(
            'THE INSIDE COVER',
            MorePalette.of(context).label,
            width - 24,
          ),
        ) +
        12 +
        measure('Make it yours', _titleStyle(context), width) +
        (_largeText(context)
            ? 0
            : 8 +
                  measure(
                    'Small details. A space that feels like you.',
                    _descriptionStyle(context),
                    width,
                  ));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'THE INSIDE COVER',
              style: MorePalette.of(context).label,
            ),
          ),
          const MoreOrnament(size: 24),
        ],
      ),
      const SizedBox(height: 12),
      Text('Make it yours', style: _titleStyle(context)),
      if (!_largeText(context)) ...[
        const SizedBox(height: 8),
        Text(
          'Small details. A space that feels like you.',
          style: _descriptionStyle(context),
        ),
      ],
    ],
  );
}
