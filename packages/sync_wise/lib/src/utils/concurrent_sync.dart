/// Limits independent network operations while waiting for every started
/// operation to settle, including when one fails. Database merges stay serial.
Future<void> forEachConcurrent<T>(
  Iterable<T> items,
  Future<void> Function(T) action, {
  int concurrency = 4,
}) async {
  assert(concurrency > 0);
  final iterator = items.iterator;
  Future<void> worker() async {
    while (iterator.moveNext()) {
      await action(iterator.current);
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
}
