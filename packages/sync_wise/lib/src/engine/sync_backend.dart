import '../auth/sync_auth.dart';
import 'sync_client.dart';

/// One authenticated attempt. Native providers need not use HTTP clients.
abstract interface class SyncSession {
  SyncClient get client;
  void close();
}

/// Implement this together with SyncAuth and SyncClient to add a provider.
abstract interface class SyncBackend {
  String get id;
  String get displayName;
  SyncAuth get auth;
  Future<SyncSession?> openSession();
  void dispose();
}
