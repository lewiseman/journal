import 'package:objectbox/objectbox.dart';
import 'package:sync_wise/sync_wise.dart';

import 'package:journal/objectbox/objectbox.g.dart' show SyncRecordEntity_;

@Entity()
class SyncRecordEntity {
  @Id()
  int id;
  @Unique()
  String key;
  String value;
  SyncRecordEntity({this.id = 0, required this.key, required this.value});
}

class JournalSyncKeyValueStore implements SyncKeyValueStore {
  final Box<SyncRecordEntity> box;
  JournalSyncKeyValueStore(Store store) : box = store.box<SyncRecordEntity>();
  SyncRecordEntity? _find(String key) {
    final query = box.query(SyncRecordEntity_.key.equals(key)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  String? read(String key) => _find(key)?.value;
  @override
  void write(String key, String value) => box.put(
    SyncRecordEntity(id: _find(key)?.id ?? 0, key: key, value: value),
  );
  @override
  void remove(String key) {
    final record = _find(key);
    if (record != null) box.remove(record.id);
  }

  @override
  List<String> keys(String prefix) {
    final query = box.query(SyncRecordEntity_.key.startsWith(prefix)).build();
    try {
      return query.find().map((record) => record.key).toList();
    } finally {
      query.close();
    }
  }

  @override
  void clear() => box.removeAll();
}
