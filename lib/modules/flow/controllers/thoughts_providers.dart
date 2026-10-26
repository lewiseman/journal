import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/flow/controllers/thoughts_repository.dart';
import 'package:journal/modules/flow/models/thought_entity.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

final thoughtsRepositoryProvider = Provider<ThoughtsRepository>((ref) {
  final changes = ref.watch(journalChangesProvider);
  return ThoughtsRepository(
    db: ref.watch(objectBoxProvider),
    device: ref.watch(deviceIdentityProvider),
    sync: ref.watch(syncStateStoreProvider),
    onDataChanged: () {
      if (!changes.isClosed) changes.add(null);
    },
  );
});

final thoughtsStreamProvider = StreamProvider<List<ThoughtEntity>>(
  (ref) => ref.watch(thoughtsRepositoryProvider).watchThoughts(),
  retry: (_, _) => null,
);
