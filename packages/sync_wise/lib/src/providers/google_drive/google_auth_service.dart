import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sync_wise/src/auth/sync_account_binding.dart';
import 'package:sync_wise/src/auth/sync_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

class AuthenticatedHttpClient extends http.BaseClient {
  final Future<Map<String, String>> Function() _getHeaders;
  final http.Client _inner;

  AuthenticatedHttpClient(this._getHeaders, {http.Client? inner})
    : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await _getHeaders().timeout(const Duration(seconds: 30));
    request.headers.addAll(headers);
    final response = await _inner
        .send(request)
        .timeout(const Duration(seconds: 45));
    return http.StreamedResponse(
      response.stream.timeout(const Duration(seconds: 45)),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class GoogleAuthService implements SyncAuth {
  /// Injected via --dart-define=GOOGLE_SERVER_CLIENT_ID=...
  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// Injected via --dart-define=GOOGLE_CLIENT_ID=... (optional)
  static const String clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

  static const List<String> scopes = [
    'email',
    drive.DriveApi.driveAppdataScope,
  ];

  final GoogleSignIn _googleSignIn;
  final SyncAccountBinding _binding;
  final http.Client Function() _clientFactory;
  GoogleSignInAccount? _currentUser;
  late final StreamSubscription<GoogleSignInAccount?> _subscription;

  GoogleAuthService({
    GoogleSignIn? googleSignIn,
    http.Client Function()? clientFactory,
    Future<Directory> Function()? directory,
    SyncAccountBinding? accountBinding,
  }) : _binding = accountBinding ?? SyncAccountBinding(directory: directory),
       _clientFactory = clientFactory ?? http.Client.new,
       _googleSignIn =
           googleSignIn ??
           GoogleSignIn(
             serverClientId: serverClientId.isNotEmpty ? serverClientId : null,
             clientId: clientId.isNotEmpty ? clientId : null,
             scopes: scopes,
           ) {
    _subscription = _googleSignIn.onCurrentUserChanged.listen((user) {
      _currentUser = user;
    });
  }

  void dispose() => _subscription.cancel();

  @override
  SyncAccount? get currentUser => _account(_currentUser);

  static SyncAccount? _account(GoogleSignInAccount? user) => user == null
      ? null
      : SyncAccount(
          id: user.id,
          email: user.email,
          displayName: user.displayName,
        );
  @override
  bool get isSignedIn => _currentUser != null;

  @override
  Stream<SyncAccount?> get onAuthStateChanged =>
      _googleSignIn.onCurrentUserChanged.map(_account);

  /// Interactive sign in when user taps the "Connect Account" button.
  @override
  Future<SyncAccount?> signIn() async {
    try {
      debugPrint(
        'Initiating Google Sign-In with serverClientId: ${serverClientId.isNotEmpty ? serverClientId : "(not set)"}',
      );
      _currentUser = await _googleSignIn.signIn();

      if (_currentUser != null) {
        // Android does not implement canAccessScopes. requestScopes checks
        // existing grants and asks only when Drive authorization is missing.
        if (!await _googleSignIn.requestScopes(scopes)) {
          throw StateError(
            'Google Drive access was not granted. Connect again to enable backup.',
          );
        }
      }

      return currentUser;
    } catch (e) {
      debugPrint('Google Sign-In failed with error: $e');
      rethrow;
    }
  }

  /// Signs out the current account.
  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  /// Returns an authenticated HTTP Client for Drive API calls.
  Future<http.Client?> getAuthenticatedClient() async {
    if (_currentUser == null) {
      await trySilentSignIn();
    }
    if (_currentUser == null) return null;

    final user = _currentUser!;
    await _binding.verify(backendId: 'google_drive', accountId: user.id);
    return RetryClient(
      AuthenticatedHttpClient(() {
        if (_currentUser?.id != user.id) {
          throw StateError('Google account changed during sync. Please retry.');
        }
        return user.authHeaders;
      }, inner: _clientFactory()),
      retries: 1,
      when: (response) => response.statusCode == 401,
      delay: (_) => Duration.zero,
      onRetry: (_, _, _) => user.clearAuthCache(),
    );
  }

  /// Attempts silent sign in on app cold launch without showing UI.
  @override
  Future<SyncAccount?> trySilentSignIn() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      return currentUser;
    } catch (e) {
      debugPrint('Silent Google Sign-In not available: $e');
      return null;
    }
  }
}
