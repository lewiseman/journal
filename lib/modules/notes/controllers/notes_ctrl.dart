import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final notesController = AsyncNotifierProvider(NotesNotifier.new);

class NotesNotifier extends AsyncNotifier {
  @override
  FutureOr<dynamic> build() {
    // TODO: implement build
    throw UnimplementedError();
  }
}
