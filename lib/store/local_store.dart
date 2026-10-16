import 'dart:convert';
import 'dart:io';

import 'blob_sha.dart';
import 'paths.dart';
import 'sync_state.dart';

const _recentCap = 50;

/// The device's copy of the note tree, plus its [SyncState].
///
/// Paths are posix and relative to [root]. Every write goes through a
/// temporary file and a rename, so a crash never leaves half a note.
class LocalStore {
  final Directory root;
  final File stateFile;
  SyncState state;

  LocalStore._(this.root, this.stateFile, this.state);

  static Future<LocalStore> open(Directory root, File stateFile) async {
    await root.create(recursive: true);
    var state = SyncState();
    if (await stateFile.exists()) {
      state = SyncState.fromJson(
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>);
    }
    return LocalStore._(root, stateFile, state);
  }

  Future<void> saveState() async {
    await stateFile.parent.create(recursive: true);
    await _atomicWrite(stateFile, utf8.encode(jsonEncode(state.toJson())));
  }

  File _file(String path) => File('${root.path}/$path');
  Directory _dir(String path) =>
      Directory(path.isEmpty ? root.path : '${root.path}/$path');

  String _rel(FileSystemEntity e) =>
      e.path.substring(root.path.length + 1).replaceAll('\\', '/');

  Future<List<String>> _trackedFiles() async {
    final out = <String>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final rel = _rel(e);
        if (isTracked(rel)) out.add(rel);
      }
    }
    out.sort();
    return out;
  }

  /// Tracked path → git blob SHA of its current content.
  Future<Map<String, String>> localShas() async => {
        for (final p in await _trackedFiles())
          p: gitBlobSha(await _file(p).readAsBytes()),
      };

  Future<List<int>?> readBytes(String path) async {
    final f = _file(path);
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<String?> readNote(String path) async {
    final b = await readBytes(path);
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  Future<void> writeBytes(String path, List<int> bytes) async {
    final f = _file(path);
    await f.parent.create(recursive: true);
    await _atomicWrite(f, bytes);
  }

  Future<void> writeNote(String path, String content) =>
      writeBytes(path, utf8.encode(content));

  /// Remove a file, then prune parent folders left empty (a folder holding
  /// `.keep` is not empty, so explicit folders survive).
  Future<void> delete(String path) async {
    final f = _file(path);
    if (await f.exists()) await f.delete();
    state.recent.remove(path);
    await _prune(parentOf(path));
  }

  Future<void> _prune(String folder) async {
    while (folder.isNotEmpty) {
      final d = _dir(folder);
      if (!await d.exists() || !await d.list().isEmpty) return;
      await d.delete();
      folder = parentOf(folder);
    }
  }

  Future<void> createFolder(String folder) async {
    final keep = _file(joinPath(folder, keepFile));
    if (!await keep.exists()) await writeBytes(joinPath(folder, keepFile), []);
  }

  /// Delete [folder] and everything in it.
  Future<void> deleteFolder(String folder) async {
    final d = _dir(folder);
    if (await d.exists()) await d.delete(recursive: true);
    state.recent.removeWhere((p, _) => isUnder(p, folder));
    await _prune(parentOf(folder));
  }

  /// Move a note or a whole folder. Refuses to overwrite.
  Future<void> move(String from, String to) async {
    if (from == to) return;
    final isFile = await _file(from).exists();
    final target = isFile ? _file(to) : _dir(to);
    if (await target.exists() ||
        (isFile && await _dir(to).exists()) ||
        (!isFile && await _file(to).exists())) {
      throw FileSystemException('target exists', to);
    }
    await target.parent.create(recursive: true);
    if (isFile) {
      await _file(from).rename(_file(to).path);
    } else {
      await _dir(from).rename(_dir(to).path);
    }
    final moved = <String, int>{};
    state.recent.removeWhere((p, t) {
      if (p == from) {
        moved[to] = t;
        return true;
      }
      if (!isFile && isUnder(p, from)) {
        moved['$to${p.substring(from.length)}'] = t;
        return true;
      }
      return false;
    });
    state.recent.addAll(moved);
    await _prune(parentOf(from));
  }

  /// All note paths (tracked `.md`), sorted.
  Future<List<String>> notePaths() async =>
      [for (final p in await _trackedFiles()) if (!isKeep(p)) p];

  /// All folders at any depth, hidden ones excluded, sorted.
  Future<List<String>> folders() async {
    final out = <String>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is Directory) {
        final rel = _rel(e);
        if (!rel.split('/').any((s) => s.startsWith('.'))) out.add(rel);
      }
    }
    out.sort();
    return out;
  }

  void touch(String path, {DateTime? at}) {
    state.recent[path] = (at ?? DateTime.now()).millisecondsSinceEpoch;
    if (state.recent.length > _recentCap) {
      final byAge = state.recent.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in byAge.take(state.recent.length - _recentCap)) {
        state.recent.remove(e.key);
      }
    }
  }

  /// Recently opened or edited notes on this device, newest first. Notes
  /// that no longer exist are skipped.
  List<String> recentPaths({int limit = 10}) {
    final byAge = state.recent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in byAge)
        if (_file(e.key).existsSync()) e.key,
    ].take(limit).toList();
  }

  static Future<void> _atomicWrite(File f, List<int> bytes) async {
    final name = f.uri.pathSegments.last;
    final tmp = File('${f.parent.path}/.$name.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }
}
