import 'package:journal/common.dart';
import 'package:sync_wise/google_drive.dart';
import 'package:sync_wise/sync_wise.dart';

final Provider<GoogleAuthService> googleAuthServiceProvider =
    Provider<GoogleAuthService>((ref) {
      final auth = GoogleAuthService();
      ref.onDispose(auth.dispose);
      return auth;
    });

final syncBackendProvider = Provider<SyncBackend>((ref) {
  final backend = GoogleDriveBackend(
    auth: ref.watch(googleAuthServiceProvider),
    // documentIdFields: const {'note': 'uuid', 'diary': 'dateString'},
  );
  ref.onDispose(backend.dispose);
  return backend;
});

final syncAuthProvider = Provider<SyncAuth>(
  (ref) => ref.watch(syncBackendProvider).auth,
);

final authStateProvider = StreamProvider<SyncAccount?>((ref) {
  return ref.watch(syncAuthProvider).onAuthStateChanged;
});

final syncEngineProvider = NotifierProvider<SyncEngine, SyncEngineState>(() {
  return SyncEngine(backendProvider: syncBackendProvider);
});
