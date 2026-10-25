import 'package:journal/common.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'objectbox.g.dart';

late ObjectBox objectbox;

class ObjectBox {
  late final Store store;
  late final Box<NoteEntity> noteBox;

  ObjectBox._create(this.store) {
    noteBox = Box<NoteEntity>(store);
  }

  static Future<ObjectBox> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final store = await openStore(
      directory: p.join(docsDir.path, "Journal-wise"),
    );
    return ObjectBox._create(store);
  }
}
