import 'dart:convert';

import '../format/slug.dart';
import '../store/blob_sha.dart';
import '../store/local_store.dart';
import '../store/paths.dart';
import 'remote_repo.dart';

class SyncResult {
  int downloaded = 0;
  int deleted = 0;
  int pushed = 0;

  /// Paths of conflict copies created by this sync.
  final List<String> conflicts = [];

  /// Set when the sync did not complete; local changes are kept.
  String? error;
  bool authError = false;
  bool offline = false;

  bool get ok => error == null;
}

/// Two-way sync between a [LocalStore] and a [RemoteRepo].
///
/// A sync is a pull then a push. Local changes are found by content hash
/// against the SHA recorded at the last sync, so nothing depends on the app
/// having exited cleanly. Text is never merged and never dropped: when both
/// sides changed a note differently, the local version is kept as a
/// `.conflict-` copy next to the remote one.
class SyncEngine {
  final LocalStore store;
  final RemoteRepo remote;
  final String device;
  final DateTime Function() clock;

  SyncEngine(this.store, this.remote,
      {required this.device, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  Future<SyncResult> sync() async {
    final result = SyncResult();
    try {
      await _pull(result);
      try {
        await _push(result);
      } on NonFastForwardException {
        await _pull(result);
        try {
          await _push(result);
        } on NonFastForwardException {
          result.error = 'sync pending: remote moved twice';
        }
      }
    } on AuthException catch (e) {
      result.authError = true;
      result.error = 'token invalid or expired (HTTP ${e.status})';
    } on RemoteException catch (e) {
      result.offline = e.offline;
      result.error = e.message;
    } finally {
      await store.saveState();
    }
    return result;
  }

  /// Number of tracked paths that differ from the last synced state.
  Future<int> pendingCount() async => (await _localChanges()).length;

  Future<Map<String, String?>> _localChanges() async {
    final local = await store.localShas();
    final base = store.state.base;
    return {
      for (final e in local.entries)
        if (base[e.key] != e.value) e.key: e.value,
      for (final p in base.keys)
        if (!local.containsKey(p)) p: null,
    };
  }

  Future<void> _pull(SyncResult result) async {
    final head = await remote.headSha();
    final state = store.state;
    if (head == state.head) return;

    final remoteTree = {
      for (final e in (await remote.tree(head)).entries)
        if (isTracked(e.key)) e.key: e.value,
    };
    final local = await store.localShas();
    final base = state.base;
    final paths = {...base.keys, ...remoteTree.keys, ...local.keys};

    for (final p in paths) {
      final b = base[p], r = remoteTree[p], l = local[p];
      if (r == b) continue; // remote unchanged: local side wins
      if (l == r) {
        _setBase(p, r); // converged
      } else if (l == b) {
        await _applyRemote(p, r, result);
      } else if (r == null) {
        base.remove(p); // deleted remotely, edited here: re-create
      } else if (l == null || isKeep(p)) {
        await _applyRemote(p, r, result); // an edit beats a deletion
      } else {
        await _conflict(p, r, result);
      }
    }
    state.head = head;
  }

  void _setBase(String path, String? sha) {
    if (sha == null) {
      store.state.base.remove(path);
    } else {
      store.state.base[path] = sha;
    }
  }

  Future<void> _applyRemote(String path, String? sha, SyncResult result) async {
    if (sha == null) {
      await store.delete(path);
      result.deleted++;
    } else {
      await store.writeBytes(path, await remote.blob(sha));
      result.downloaded++;
    }
    _setBase(path, sha);
  }

  Future<void> _conflict(String path, String remoteSha, SyncResult result) async {
    final mine = await store.readBytes(path);
    final copy = await _conflictPath(path);
    await store.writeBytes(copy, _markConflict(mine!));
    await _applyRemote(path, remoteSha, result);
    result.conflicts.add(copy);
  }

  Future<String> _conflictPath(String path) async {
    final t = clock();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
    final stem = path.endsWith('.md') ? path.substring(0, path.length - 3) : path;
    final name = '$stem.conflict-${slugify(device)}-$stamp';
    var candidate = '$name.md';
    for (var i = 2; await store.readBytes(candidate) != null; i++) {
      candidate = '$name-$i.md';
    }
    return candidate;
  }

  static List<int> _markConflict(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    if (!text.startsWith('# ')) return bytes;
    final nl = text.indexOf('\n');
    final title = nl < 0 ? text : text.substring(0, nl);
    final rest = nl < 0 ? '' : text.substring(nl);
    return utf8.encode('$title (conflict)$rest');
  }

  Future<void> _push(SyncResult result) async {
    final changed = await _localChanges();
    if (changed.isEmpty) return;

    // Read each file once; the SHA recorded must be that of the bytes sent,
    // so an edit made while pushing is still seen as pending afterwards.
    final changes = <String, List<int>?>{};
    final shas = <String, String?>{};
    for (final p in changed.keys) {
      final bytes = await store.readBytes(p);
      changes[p] = bytes;
      shas[p] = bytes == null ? null : gitBlobSha(bytes);
    }

    final newHead = await remote.commit(
      parent: store.state.head!,
      changes: changes,
      message: 'easynote: $device: ${_summary(changes)}',
    );
    shas.forEach(_setBase);
    store.state.head = newHead;
    result.pushed += changes.length;
  }

  String _summary(Map<String, List<int>?> changes) {
    if (changes.length > 1) return '${changes.length} changes';
    final p = changes.keys.single;
    if (changes[p] == null) return 'delete $p';
    return store.state.base.containsKey(p) ? 'edit $p' : 'add $p';
  }
}
