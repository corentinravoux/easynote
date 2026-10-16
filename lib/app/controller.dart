import 'dart:async';

import 'package:flutter/foundation.dart';

import '../format/note.dart';
import '../format/slug.dart';
import '../store/local_store.dart';
import '../store/paths.dart';
import '../sync/remote_repo.dart';
import '../sync/sync_engine.dart';

/// Virtual folder listing this device's recently opened notes.
const recentFolder = '@recent';

class NoteSummary {
  final String path;
  final String title;
  final List<String> preview;

  /// The same items as [preview], structured, for cards that draw their own
  /// bullets and checkboxes.
  final List<NoteLine> previewLines;
  final int todoCount, doneCount;
  final String _haystack;

  NoteSummary(this.path, Note note)
      : title = displayTitle(path, note),
        preview = previewOf(note),
        previewLines = note.lines.where((l) => l.text.trim().isNotEmpty).take(6).toList(),
        todoCount = note.todoCount,
        doneCount = note.doneCount,
        _haystack = fold([note.title, for (final l in note.lines) l.text].join('\n'));

  bool get conflict => basenameOf(path).contains('.conflict-');
  String get folder => parentOf(path);
  bool matches(String foldedQuery) => _haystack.contains(foldedQuery);
}

String displayTitle(String path, Note note) {
  if (note.title.trim().isNotEmpty) return note.title.trim();
  final base = basenameOf(path);
  return base.endsWith('.md') ? base.substring(0, base.length - 3) : base;
}

enum SyncPhase { localOnly, idle, syncing, synced, pending, offline, authError, error }

class SyncStatus {
  final SyncPhase phase;
  final int pending;
  final String? message;
  const SyncStatus(this.phase, {this.pending = 0, this.message});
}

/// UI-facing state: the note list, the current folder and search, and sync.
class AppController extends ChangeNotifier {
  final LocalStore store;

  /// Builds the remote from current settings; returns null when sync is not
  /// configured, in which case the app works on local files only.
  RemoteRepo? Function() remoteFactory;
  String device;

  AppController({
    required this.store,
    required this.remoteFactory,
    required this.device,
  });

  final Map<String, NoteSummary> _notes = {};
  List<String> _folders = [];

  /// Set by an open editor: saves its text and syncs. Called before the
  /// desktop window closes.
  Future<void> Function()? flushEditor;

  String _folder = '';
  String _query = '';
  SyncStatus status = const SyncStatus(SyncPhase.idle);
  Future<SyncResult?>? _running;

  String get folder => _folder;
  String get query => _query;
  List<String> get allFolders => _folders;

  set folder(String f) {
    _folder = f;
    notifyListeners();
  }

  set query(String q) {
    _query = q;
    notifyListeners();
  }

  /// Folders directly inside [parent].
  List<String> childFolders(String parent) => [
        for (final f in _folders)
          if (parentOf(f) == parent) f,
      ];

  List<String> get subfolders =>
      _folder == recentFolder || _query.isNotEmpty ? [] : childFolders(_folder);

  /// Notes for the current view: search results across all folders, the
  /// recent list, or the notes of the current folder sorted by title.
  List<NoteSummary> get notes {
    if (_query.trim().isNotEmpty) {
      final q = fold(_query.trim());
      return _sorted(_notes.values.where((n) => n.matches(q)));
    }
    if (_folder == recentFolder) {
      return [
        for (final p in store.recentPaths(limit: 30))
          if (_notes[p] != null) _notes[p]!,
      ];
    }
    return _sorted(_notes.values.where((n) => n.folder == _folder));
  }

  List<NoteSummary> recent({int limit = 10}) => [
        for (final p in store.recentPaths(limit: limit))
          if (_notes[p] != null) _notes[p]!,
      ];

  NoteSummary? summary(String path) => _notes[path];

  int countUnder(String folder) =>
      _notes.keys.where((p) => isUnder(p, folder)).length;

  List<NoteSummary> _sorted(Iterable<NoteSummary> it) => it.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  /// Re-read every note from disk.
  Future<void> reload() async {
    _notes.clear();
    for (final p in await store.notePaths()) {
      final text = await store.readNote(p);
      if (text != null) _notes[p] = NoteSummary(p, parseNote(text));
    }
    _folders = await store.folders();
    if (_folder != recentFolder && _folder.isNotEmpty && !_folders.contains(_folder)) {
      _folder = '';
    }
    notifyListeners();
  }

  Future<Note?> load(String path) async {
    final text = await store.readNote(path);
    if (text == null) return null;
    store.touch(path);
    await store.saveState();
    return parseNote(text);
  }

  /// Sync now. Concurrent calls share one run.
  Future<SyncResult?> sync() {
    return _running ??= _sync().whenComplete(() => _running = null);
  }

  Future<SyncResult?> _sync() async {
    final remote = remoteFactory();
    if (remote == null) {
      status = const SyncStatus(SyncPhase.localOnly);
      notifyListeners();
      return null;
    }
    status = const SyncStatus(SyncPhase.syncing);
    notifyListeners();
    final engine = SyncEngine(store, remote, device: device.isEmpty ? 'device' : device);
    final r = await engine.sync();
    await reload();
    final pending = await engine.pendingCount();
    if (r.authError) {
      status = SyncStatus(SyncPhase.authError, pending: pending, message: r.error);
    } else if (r.offline) {
      status = SyncStatus(SyncPhase.offline, pending: pending);
    } else if (r.error != null) {
      status = SyncStatus(SyncPhase.error, pending: pending, message: r.error);
    } else if (pending > 0) {
      status = SyncStatus(SyncPhase.pending, pending: pending);
    } else {
      status = SyncStatus(SyncPhase.synced,
          message: r.conflicts.isEmpty
              ? null
              : '${r.conflicts.length} conflict${r.conflicts.length > 1 ? 's' : ''}: both versions kept');
    }
    notifyListeners();
    return r;
  }

  /// Write [note] to [path] if its text changed, then optionally sync.
  ///
  /// [basedOn] is the file text the editor started from. If the file changed
  /// on disk since (a sync brought another device's version), [note] is
  /// written to a conflict copy instead, so neither version is lost. Returns
  /// the path actually written.
  Future<String> saveNote(String path, Note note,
      {bool push = true, String? basedOn}) async {
    final text = serializeNote(note);
    final onDisk = await store.readNote(path);
    var target = path;
    if (basedOn != null && onDisk != null && onDisk != basedOn && onDisk != text) {
      target = await conflictCopyPath(store, path, device.isEmpty ? 'device' : device, DateTime.now());
      notice = 'This note changed on another device. Your version is saved as a copy next to it.';
    }
    if (target != path || onDisk != text) {
      await store.writeNote(target, text);
      _notes[target] = NoteSummary(target, note);
    }
    store.touch(target);
    await store.saveState();
    notifyListeners();
    if (push) await sync();
    return target;
  }

  /// A one-off message for the user; the UI shows it and clears it.
  String? notice;

  /// Save a note that has no file yet. Returns its new path, or null when
  /// the note is empty and was discarded.
  Future<String?> saveNewNote(String folder, Note note, {bool push = true}) async {
    final hasText = note.title.trim().isNotEmpty ||
        note.lines.any((l) => l.text.trim().isNotEmpty);
    if (!hasText) return null;
    final seed = note.title.trim().isNotEmpty
        ? note.title
        : note.lines.firstWhere((l) => l.text.trim().isNotEmpty).text;
    final path = uniquePath(folder == recentFolder ? '' : folder, seed, _notes.keys.toSet());
    return saveNote(path, note, push: push);
  }

  /// Rename a note's file after its title and/or move it to [toFolder].
  Future<String> moveNote(String from, String toFolder) async {
    final note = await load(from);
    final others = _notes.keys.where((p) => p != from).toSet();
    final to = uniquePath(toFolder, displayTitle(from, note!), others);
    if (to != from) {
      await store.move(from, to);
      await reload();
      await sync();
    }
    return to;
  }

  Future<void> deleteNote(String path) async {
    await store.delete(path);
    _notes.remove(path);
    await store.saveState();
    await reload();
    await sync();
  }

  static String cleanFolderName(String name) => name
      .trim()
      .replaceAll(RegExp(r'[/\\]'), '-')
      .replaceAll(RegExp(r'^\.+'), '')
      .trim();

  Future<String?> createFolder(String parent, String name) async {
    final clean = cleanFolderName(name);
    if (clean.isEmpty) return null;
    final path = joinPath(parent, clean);
    await store.createFolder(path);
    await reload();
    await sync();
    return path;
  }

  Future<void> moveFolder(String from, String to) async {
    await store.move(from, to);
    if (isUnder(_folder, from) || _folder == from) {
      _folder = to + _folder.substring(from.length);
    }
    await reload();
    await sync();
  }

  /// Delete a folder that holds no notes (subfolders included).
  Future<bool> deleteFolder(String folder) async {
    if (countUnder(folder) > 0) return false;
    await store.deleteFolder(folder);
    if (isUnder(_folder, folder) || _folder == folder) _folder = parentOf(folder);
    await reload();
    await sync();
    return true;
  }
}
