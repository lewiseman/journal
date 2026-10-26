import 'package:http/http.dart' as http;

import '../../engine/sync_backend.dart';
import 'drive_sync_client.dart';
import 'google_auth_service.dart';

/// Owns Google auth and authenticated client sessions.
class GoogleDriveBackend implements SyncBackend {
  @override
  final GoogleAuthService auth;
  final DriveSyncClient Function(http.Client)? clientFactory;
  final Map<String, String> documentIdFields;
  final bool _ownsAuth;

  GoogleDriveBackend({
    GoogleAuthService? auth,
    this.clientFactory,
    this.documentIdFields = const {},
  }) : auth = auth ?? GoogleAuthService(),
       _ownsAuth = auth == null;

  @override
  String get id => 'google_drive';
  @override
  String get displayName => 'Google Drive';

  @override
  Future<SyncSession?> openSession() async {
    final httpClient = await auth.getAuthenticatedClient();
    if (httpClient == null) return null;
    try {
      return _DriveSession(
        httpClient,
        clientFactory?.call(httpClient) ??
            DriveSyncClient(httpClient, documentIdFields: documentIdFields),
      );
    } catch (_) {
      httpClient.close();
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_ownsAuth) auth.dispose();
  }
}

class _DriveSession implements SyncSession {
  final http.Client _httpClient;
  @override
  final DriveSyncClient client;

  _DriveSession(this._httpClient, this.client);

  @override
  void close() => _httpClient.close();
}
