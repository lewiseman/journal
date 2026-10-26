import 'package:journal/common.dart';

import 'diary_repository.dart';

final Provider<DiaryRepository> diaryRepositoryProvider =
    Provider<DiaryRepository>((ref) {
      final changes = ref.watch(journalChangesProvider);
      return DiaryRepository(
        db: ref.watch(objectBoxProvider),
        device: ref.watch(deviceIdentityProvider),
        sync: ref.watch(syncStateStoreProvider),
        onDataChanged: () {
          if (!changes.isClosed) changes.add(null);
        },
      );
    });

final diaryDaysProvider = StreamProvider<List<DiaryDayEntity>>(
  (ref) => ref.watch(diaryRepositoryProvider).watchAllDays(),
);
