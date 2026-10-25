/// Account details that do not expose a provider's SDK or credentials.
class SyncAccount {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  const SyncAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });
}

/// Authentication belongs to the backend, including restoring native sessions.
/// An iCloud implementation may use the device account without a sign-in UI.
abstract interface class SyncAuth {
  SyncAccount? get currentUser;
  bool get isSignedIn;
  Stream<SyncAccount?> get onAuthStateChanged;
  Future<SyncAccount?> trySilentSignIn();
  Future<SyncAccount?> signIn();
  Future<void> signOut();
}
