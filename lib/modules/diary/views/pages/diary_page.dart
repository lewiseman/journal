import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_header.dart';

const _backgroundScrollDistance = 120.0;
const _backgroundTravel = 28.0;

class DiaryPage extends StatefulWidget {
  const new({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final today = DateTime.now();
  final _scroll = ScrollController();
  late final DateTime _selectedDate = DateTime(
    today.year,
    today.month,
    today.day,
  );

  double get _controlsHeight =>
      (MediaQuery.textScalerOf(context).scale(13) + 26).clamp(
        44.0,
        double.infinity,
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final artworkWidth = width.clamp(0.0, 700.0);
    return Stack(
      children: [
        Positioned(
          top: 100 - artworkWidth * .41,
          left: (width - artworkWidth) / 2,
          width: artworkWidth,
          child: AnimatedBuilder(
            animation: _scroll,
            child: Opacity(
              opacity: Theme.of(context).brightness == Brightness.dark
                  ? .6
                  : .16,
              child: Image.asset(
                'assets/images/diary_top_bg.png',
                color: context.colors.primary,
                colorBlendMode: BlendMode.color,
                fit: BoxFit.fitWidth,
                excludeFromSemantics: true,
              ),
            ),
            builder: (context, child) {
              final progress = _scroll.hasClients
                  ? (_scroll.offset / _backgroundScrollDistance).clamp(0.0, 1.0)
                  : 0.0;
              // Let the artwork drift with the feed, then gently settle.
              final travel =
                  _backgroundTravel * Curves.easeOutCubic.transform(progress);
              return Transform.translate(
                offset: Offset(0, -travel),
                child: child,
              );
            },
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .13, .27, .42, 1],
                colors: [
                  context.colors.surface.withValues(alpha: 0.627),
                  context.colors.surface.withValues(alpha: 0.094),
                  context.colors.surface.withValues(alpha: 0.863),
                  context.colors.surface,
                  context.colors.surface,
                ],
              ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Scrollbar(
                      child: CustomScrollView(
                        key: const PageStorageKey('diary-timeline'),
                        controller: _scroll,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: [
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: DiaryHeaderDelegate(
                              topInset: top,
                              selectedDate: _selectedDate,
                              controlsHeight: _controlsHeight,
                              onDateChanged: (date) {},
                              onSearch: () {},
                              onPickDate: () {},
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Container(
                                color: Colors.red,
                                height: 400,
                                child: Text('Active date diary'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
