import 'dart:convert';
import 'dart:io';

import 'package:easynote/store/blob_sha.dart';
import 'package:easynote/store/local_store.dart';
import 'package:easynote/store/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late LocalStore store;

  Future<LocalStore> openStore() =>
      LocalStore.open(Directory('${tmp.path}/notes'), File('${tmp.path}/state.json'));

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('easynote_store_');
    store = await openStore();
  });
  tearDown(() => tmp.delete(recursive: true));

  test('state JSON round trip', () {
    final s = SyncState(head: 'abc', base: {'a.md': '1'}, recent: {'a.md': 5});
    final back = SyncState.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(back.head, 'abc');
    expect(back.base, {'a.md': '1'});
    expect(back.recent, {'a.md': 5});
  });

  test('missing state file gives empty state', () {
    expect(store.state.head, isNull);
    expect(store.state.base, isEmpty);
  });

  test('state persists across reopen', () async {
    store.state.head = 'h1';
    await store.saveState();
    final again = await openStore();
    expect(again.state.head, 'h1');
  });

  test('writeBytes creates folders; localShas lists tracked files only', () async {
    await store.writeBytes('lya/tomo/maps.md', utf8.encode('# Maps\n'));
    await store.writeBytes('notes.txt', utf8.encode('x'));
    await File('${store.root.path}/.hidden.md').writeAsString('x');
    final shas = await store.localShas();
    expect(shas.keys, ['lya/tomo/maps.md']);
    expect(shas['lya/tomo/maps.md'], gitBlobSha(utf8.encode('# Maps\n')));
  });

  test('writes leave no temporary files behind', () async {
    await store.writeBytes('a.md', utf8.encode('x'));
    final names = store.root.listSync().map((e) => e.uri.pathSegments.last);
    expect(names, ['a.md']);
  });

  test('delete keeps a folder with .keep, prunes one without', () async {
    await store.createFolder('kept');
    await store.writeBytes('kept/a.md', utf8.encode('x'));
    await store.writeBytes('gone/sub/b.md', utf8.encode('x'));
    await store.delete('kept/a.md');
    await store.delete('gone/sub/b.md');
    expect(Directory('${store.root.path}/kept').existsSync(), isTrue);
    expect(Directory('${store.root.path}/gone').existsSync(), isFalse);
    expect(await store.folders(), ['kept']);
  });

  test('move of a folder moves notes and rewrites recent keys', () async {
    await store.writeBytes('lya/p1d.md', utf8.encode('# P1D\n'));
    await store.writeBytes('lya/tomo/maps.md', utf8.encode('# Maps\n'));
    store.touch('lya/tomo/maps.md');
    await store.move('lya', 'archive/lya');
    expect(await store.notePaths(), ['archive/lya/p1d.md', 'archive/lya/tomo/maps.md']);
    expect(store.recentPaths(), ['archive/lya/tomo/maps.md']);
    expect(Directory('${store.root.path}/lya').existsSync(), isFalse);
  });

  test('move of a note into a new folder', () async {
    await store.writeBytes('a.md', utf8.encode('x'));
    await store.move('a.md', 'x/y/a.md');
    expect(await store.notePaths(), ['x/y/a.md']);
  });

  test('move refuses to overwrite', () async {
    await store.writeBytes('a.md', utf8.encode('x'));
    await store.writeBytes('b.md', utf8.encode('y'));
    expect(() => store.move('a.md', 'b.md'), throwsA(isA<FileSystemException>()));
  });

  test('recent is newest first, capped, and skips deleted notes', () async {
    for (var i = 0; i < 60; i++) {
      await store.writeBytes('n$i.md', utf8.encode('x'));
      store.touch('n$i.md', at: DateTime.fromMillisecondsSinceEpoch(1000 + i));
    }
    expect(store.state.recent.length, 50);
    expect(store.recentPaths(limit: 3), ['n59.md', 'n58.md', 'n57.md']);
    await store.delete('n59.md');
    expect(store.recentPaths(limit: 1), ['n58.md']);
  });

  test('folders lists nested folders sorted, hidden excluded', () async {
    await store.createFolder('b');
    await store.createFolder('a/c');
    await Directory('${store.root.path}/.git').create();
    expect(await store.folders(), ['a', 'a/c', 'b']);
  });

  test('an unsynced write survives reopen and shows as changed', () async {
    // Review focus 4: text written before any push is on disk, and detected
    // as a pending change by content hash after a restart.
    store.state.base['a.md'] = gitBlobSha(utf8.encode('old\n'));
    await store.saveState();
    await store.writeBytes('a.md', utf8.encode('new\n'));
    final again = await openStore();
    expect(await again.readNote('a.md'), 'new\n');
    expect((await again.localShas())['a.md'], isNot(again.state.base['a.md']));
  });
}
