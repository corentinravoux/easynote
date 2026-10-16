/// The remote side of sync: one branch of a git repository, reached through
/// an API rather than a clone.
abstract class RemoteRepo {
  /// Commit SHA the branch points at.
  Future<String> headSha();

  /// Every blob in [commitSha]'s tree, path → blob SHA.
  Future<Map<String, String>> tree(String commitSha);

  Future<List<int>> blob(String sha);

  /// Make one commit on top of [parent] applying [changes] (bytes to write,
  /// `null` to delete) and fast-forward the branch to it. Returns the new
  /// commit SHA. Throws [NonFastForwardException] if the branch moved.
  Future<String> commit({
    required String parent,
    required Map<String, List<int>?> changes,
    required String message,
  });
}

/// The token was refused (HTTP 401/403).
class AuthException implements Exception {
  final int status;
  const AuthException(this.status);
  @override
  String toString() => 'AuthException($status)';
}

/// The branch moved between reading it and updating it.
class NonFastForwardException implements Exception {
  const NonFastForwardException();
}

/// Network failure or unexpected response.
class RemoteException implements Exception {
  final String message;
  final bool offline;
  const RemoteException(this.message, {this.offline = false});
  @override
  String toString() => 'RemoteException($message)';
}
