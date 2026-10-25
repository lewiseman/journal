import 'package:flutter/material.dart';
import 'package:journal/common.dart';

class DiaryPage extends StatefulWidget {
  const new({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final _scroll = ScrollController();

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
          child: Image.asset('assets/images/diary_top_bg.png'),
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
                          // SliverPersistentHeader(
                          //   pinned: true,
                          //   delegate: _DiaryHeaderDelegate(
                          //     topInset: top,
                          //     selectedDate: _selectedDate,
                          //     entryDates: _entries
                          //         .map((entry) => entry.date)
                          //         .toSet(),
                          //     searching: _searching,
                          //     controlsHeight: _controlsHeight,
                          //     searchField: _buildSearchField(),
                          //     onDateChanged: (date) {},
                          //     onSearch: () {},
                          //     onPickDate: () {},
                          //   ),
                          // ),
                          SliverToBoxAdapter(),
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

/// A pinned header whose geometry follows the same scroll offset as the feed.
/// Keeping it inside the sliver layout avoids offset feedback as it contracts.
// class _DiaryHeaderDelegate extends SliverPersistentHeaderDelegate {
//   const _DiaryHeaderDelegate({
//     required this.topInset,
//     required this.selectedDate,
//     required this.entryDates,
//     required this.searching,
//     required this.controlsHeight,
//     required this.searchField,
//     required this.onDateChanged,
//     required this.onSearch,
//     required this.onPickDate,
//   });

//   final double topInset;
//   final DateTime selectedDate;
//   final Set<DateTime> entryDates;
//   final bool searching;
//   final double controlsHeight;
//   final Widget searchField;
//   final ValueChanged<DateTime> onDateChanged;
//   final VoidCallback onSearch;
//   final VoidCallback onPickDate;

//   @override
//   double get maxExtent => topInset + controlsHeight + 118;

//   @override
//   double get minExtent => topInset + 82 + (searching ? controlsHeight : 0);

//   @override
//   Widget build(
//     BuildContext context,
//     double shrinkOffset,
//     bool overlapsContent,
//   ) {
//     final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
//     final actionProgress = searching ? 1.0 : progress;
//     final actionOpacity = searching
//         ? ((progress - .45) / .25).clamp(0.0, 1.0)
//         : 1.0;
//     final expandedTop = 6 + controlsHeight / 2 - 24;
//     final actionTop =
//         topInset +
//         (searching
//             ? controlsHeight + 17 + 4 * (1 - progress)
//             : expandedTop + (17 - expandedTop) * progress);
//     final actionInset = searching ? 0.0 : 14 * (1 - progress);
//     final foreground = ClipRect(
//       child: Stack(
//         children: [
//           Column(
//             children: [
//               SizedBox(height: topInset + 6),
//               SizedBox(
//                 height: controlsHeight * (searching ? 1 : 1 - progress),
//                 child: searching
//                     ? ClipRect(
//                         child: OverflowBox(
//                           alignment: Alignment.topCenter,
//                           minHeight: controlsHeight,
//                           maxHeight: controlsHeight,
//                           child: searchField,
//                         ),
//                       )
//                     : null,
//               ),
//               SizedBox(height: 4 * (1 - progress)),
//               DiaryCalendar(
//                 selectedDate: selectedDate,
//                 entryDates: entryDates,
//                 onDateChanged: onDateChanged,
//                 collapseProgress: progress,
//               ),
//             ],
//           ),
//           Positioned(
//             left: actionInset,
//             top: actionTop,
//             width: 88 + (48 - 88) * actionProgress,
//             height: 48,
//             child: _action(
//               action: DiaryHeaderAction.date,
//               progress: actionProgress,
//               opacity: actionOpacity,
//               onTap: onPickDate,
//             ),
//           ),
//           Positioned(
//             right: actionInset,
//             top: actionTop,
//             width: 76 + (48 - 76) * actionProgress,
//             height: 48,
//             child: _action(
//               action: DiaryHeaderAction.search,
//               progress: actionProgress,
//               opacity: actionOpacity,
//               onTap: onSearch,
//             ),
//           ),
//         ],
//       ),
//     );
//     return Stack(
//       clipBehavior: Clip.none,
//       children: [
//         Positioned(
//           top: 0,
//           left: 0,
//           right: 0,
//           bottom:
//               -_DiaryHeaderGradient.fadeExtent *
//               Curves.easeOutCubic.transform(progress),
//           child: IgnorePointer(child: _DiaryHeaderGradient(progress: progress)),
//         ),
//         foreground,
//       ],
//     );
//   }

//   Widget _action({
//     required DiaryHeaderAction action,
//     required double progress,
//     required double opacity,
//     required VoidCallback onTap,
//   }) => IgnorePointer(
//     ignoring: opacity < .5,
//     child: ExcludeSemantics(
//       excluding: opacity < .5,
//       child: Opacity(
//         opacity: opacity,
//         child: DiaryHeaderControl(
//           key: ValueKey(
//             action == DiaryHeaderAction.date
//                 ? 'diary-date-control'
//                 : 'diary-search-control',
//           ),
//           collapseProgress: progress,
//           action: action,
//           date: selectedDate,
//           onTap: onTap,
//         ),
//       ),
//     ),
//   );

//   @override
//   bool shouldRebuild(_DiaryHeaderDelegate oldDelegate) =>
//       oldDelegate.topInset != topInset ||
//       oldDelegate.selectedDate != selectedDate ||
//       oldDelegate.entryDates != entryDates ||
//       oldDelegate.searching != searching ||
//       oldDelegate.controlsHeight != controlsHeight ||
//       oldDelegate.searchField != searchField;
// }
