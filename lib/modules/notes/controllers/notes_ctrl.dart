import 'dart:async';

import 'package:journal/common.dart';

final notesController = AsyncNotifierProvider(NotesNotifier.new);

class NotesNotifier extends AsyncNotifier<List<Entry>> {
  @override
  FutureOr<List<Entry>> build() {
    final values = ref
        .watch(
          entryController.select(
            (x) => x.where((y) => y.entryType == EntryType.note),
          ),
        )
        .toList();
    return Future.value(values);
  }
}
