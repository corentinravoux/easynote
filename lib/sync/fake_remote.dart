import '../store/blob_sha.dart';
import 'remote_repo.dart';

/// In-memory [RemoteRepo], for tests and for running the app without a
/// GitHub account.
class FakeRemote implements RemoteRepo {
  final _blobs = <String, List<int>>{};
  final _trees = <String, Map<String, String>>{};
  String _head;
  int _counter = 0;

  /// Number of API calls made, to check that idle syncs stay cheap.
  int calls = 0;

  /// When set, the next call throws it (then it is cleared, unless [sticky]).
  Exception? failNext;
  bool sticky = false;

  /// Runs just before each commit, to simulate another device pushing.
  void Function()? beforeCommit;

  FakeRemote([Map<String, List<int>> initial = const {}]) : _head = 'c0' {
    _trees[_head] = {};
    if (initial.isNotEmpty) externalCommit(initial);
  }

  void _call() {
    calls++;
    final f = failNext;
    if (f != null) {
      if (!sticky) failNext = null;
      throw f;
    }
  }

  /// A commit made by someone else (another device, github.com).
  void externalCommit(Map<String, List<int>?> changes) {
    _head = _apply(_head, changes);
  }

  String _apply(String parent, Map<String, List<int>?> changes) {
    final files = Map<String, String>.from(_trees[parent]!);
    changes.forEach((path, bytes) {
      if (bytes == null) {
        files.remove(path);
      } else {
        final sha = gitBlobSha(bytes);
        _blobs[sha] = List.of(bytes);
        files[path] = sha;
      }
    });
    final c = 'c${++_counter}';
    _trees[c] = files;
    return c;
  }

  /// Current files at the branch head, path → bytes.
  Map<String, List<int>> files() =>
      {for (final e in _trees[_head]!.entries) e.key: _blobs[e.value]!};

  String get head => _head;

  @override
  Future<String> headSha() async {
    _call();
    return _head;
  }

  @override
  Future<Map<String, String>> tree(String commitSha) async {
    _call();
    return Map.of(_trees[commitSha]!);
  }

  @override
  Future<List<int>> blob(String sha) async {
    _call();
    return List.of(_blobs[sha]!);
  }

  @override
  Future<String> commit({
    required String parent,
    required Map<String, List<int>?> changes,
    required String message,
  }) async {
    _call();
    beforeCommit?.call();
    if (parent != _head) throw const NonFastForwardException();
    _head = _apply(parent, changes);
    lastMessage = message;
    return _head;
  }

  String? lastMessage;
}
