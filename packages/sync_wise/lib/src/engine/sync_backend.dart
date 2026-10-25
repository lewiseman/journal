import 'package:sync_wise/src/auth/sync_auth.dart';

/// One authenticated attempt. Native providers need not use HTTP clients.
abstract interface class SyncSession {
  // SyncClient get client;
  void close();
}

/// Implement this together with SyncAuth and SyncClient to add a provider.
abstract interface class SyncBackend {
  String get id;
  String get displayName;
  String get attachmentScheme;
  SyncAuth get auth;
  // Future<SyncSession?> openSession();
  void clearCache();
  void dispose();
}
