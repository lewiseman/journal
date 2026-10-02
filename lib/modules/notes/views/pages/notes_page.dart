import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:journal/common.dart';

class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNotes = ref.watch(notesController);
    return asyncNotes.when(
      loading: () => SizedBox.shrink(),
      error: (error, stackTrace) => Center(child: Text(error.toString())),
      data: (data) {
        return MasonryGridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: data.length,
          padding: EdgeInsets.only(left: 16, right: 16, bottom: 100),
          itemBuilder: (context, index) {
            final note = data[index];
            return Container(
              color: Colors.red,
              height: 200,
              child: Column(children: [Text(note.title ?? 'Note ttle')]),
            );
          },
        );
      },
    );
  }
}
