import 'package:sync_wise/src/engine/sync_backend.dart';
import 'package:sync_wise/src/providers/google_drive/google_auth_service.dart';

class GoogleDriveBackend implements SyncBackend {
  @override
  final GoogleAuthService auth;
  final bool _ownsAuth;

  GoogleDriveBackend({GoogleAuthService? auth})
    : auth = auth ?? GoogleAuthService(),
      _ownsAuth = auth == null;

  @override
  String get id => 'google_drive';
  @override
  String get displayName => 'Google Drive';
  @override
  String get attachmentScheme => 'drive';

  @override
  void clearCache() {
    // TODO: implement clearCache
  }

  @override
  void dispose() {
    // TODO: implement dispose
  }
}
