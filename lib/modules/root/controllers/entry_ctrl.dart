import 'package:journal/common.dart';

final entryController = NotifierProvider(EntryNotifier.new);

class EntryNotifier extends Notifier<List<Entry>> {
  @override
  List<Entry> build() {
    return objectbox.entryBox.getAll();
  }
}
