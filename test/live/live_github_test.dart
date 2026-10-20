// Runs against a real, throwaway GitHub repo. Never point it at your notes.
//
//   EASYNOTE_TEST_TOKEN=github_pat_... EASYNOTE_TEST_REPO=owner/scratch-repo \
//     [EASYNOTE_TEST_BRANCH=live-test] flutter test test/live
//
// A throwaway branch of a real repo works too: the test only touches
// easynote-live-test/ and removes it at the end.
import 'dart:convert';
import 'dart:io';

import 'package:easynote/store/local_store.dart';
import 'package:easynote/sync/github_remote.dart';
import 'package:easynote/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final token = Platform.environment['EASYNOTE_TEST_TOKEN'];
  final repo = Platform.environment['EASYNOTE_TEST_REPO'];
  final branch = Platform.environment['EASYNOTE_TEST_BRANCH'] ?? 'main';
  final skip = token == null || repo == null
      ? 'set EASYNOTE_TEST_TOKEN and EASYNOTE_TEST_REPO'
      : null;

  test('two devices, one conflict, nothing lost', () async {
    final [owner, name] = repo!.split('/');
    final tmp = await Directory.systemTemp.createTemp('easynote_live_');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'easynote-live-test/$stamp.md';
    Future<SyncEngine> device(String id) async => SyncEngine(
          await LocalStore.open(Directory('${tmp.path}/$id/n'), File('${tmp.path}/$id/s.json')),
          GithubRemote(owner: owner, repo: name, branch: branch, token: token!),
          device: id,
        );
    final a = await device('a'), b = await device('b');
    try {
      expect((await a.sync()).error, isNull);
      expect((await b.sync()).error, isNull);
      await a.store.writeNote(path, '# Live\n- from a\n');
      await b.store.writeNote(path, '# Live\n- from b\n');
      expect((await a.sync()).error, isNull);
      final r = await b.sync();
      expect(r.error, isNull);
      expect(r.conflicts, hasLength(1));
      await a.sync();
      final all = await a.store.notePaths();
      final texts = [
        for (final p in all.where((p) => p.startsWith('easynote-live-test/')))
          utf8.decode((await a.store.readBytes(p))!),
      ].join();
      expect(texts, allOf(contains('from a'), contains('from b')));
    } finally {
      await a.store.deleteFolder('easynote-live-test');
      await a.sync();
      await tmp.delete(recursive: true);
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
