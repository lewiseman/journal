import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final notesController = AsyncNotifierProvider(NotesNotifier.new);

class NotesNotifier extends AsyncNotifier {
  @override
  FutureOr<dynamic> build() {
    // TODO: get all entries
    throw UnimplementedError();
  }
}
