import 'package:journal/common.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'objectbox.g.dart';

late ObjectBox objectbox;

class ObjectBox {
  late final Store store;
  late final Box<NoteEntity> noteBox;
  late final Box<DiaryDayEntity> diaryBox;
  late final Box<ThoughtEntity> thoughtBox;

  ObjectBox.fromStore(this.store) {
    noteBox = Box<NoteEntity>(store);
    diaryBox = Box<DiaryDayEntity>(store);
    thoughtBox = Box<ThoughtEntity>(store);
  }

  void close() => store.close();

  static Future<ObjectBox> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final store = await openStore(
      directory: p.join(docsDir.path, "Journal-wise"),
    );
    return ObjectBox.fromStore(store);
  }
}
