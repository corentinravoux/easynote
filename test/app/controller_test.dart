import 'dart:convert';
import 'dart:io';

import 'package:easynote/app/controller.dart';
import 'package:easynote/format/note.dart';
import 'package:easynote/store/local_store.dart';
import 'package:easynote/sync/fake_remote.dart';
import 'package:easynote/sync/remote_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late FakeRemote remote;
  late AppController c;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('easynote_ctl_');
    remote = FakeRemote({
      'lya/p1d.md': utf8.encode('# P1D\n- [ ] window\n'),
      'lya/tomo/maps.md': utf8.encode('# Maps\n- Wiener\n'),
      'flip/growth.md': utf8.encode('# Écart growth\n- fσ8\n'),
      'inbox.md': utf8.encode('# Inbox\n'),
      'lya/a.md': utf8.encode('# alpha\n'),
    });
    final store = await LocalStore.open(
        Directory('${tmp.path}/n'), File('${tmp.path}/s.json'));
    c = AppController(store: store, remoteFactory: () => remote, device: 'laptop');
    await c.sync();
  });
  tearDown(() => tmp.delete(recursive: true));

  test('folder view lists direct notes sorted by title, and subfolders', () {
    c.folder = 'lya';
    expect(c.notes.map((n) => n.title), ['alpha', 'P1D']);
    expect(c.subfolders, ['lya/tomo']);
    c.folder = '';
    expect(c.notes.map((n) => n.title), ['Inbox']);
    expect(c.subfolders, ['flip', 'lya']);
  });

  test('search spans folders and ignores accents and case', () {
    c.query = 'ecart';
    expect(c.notes.map((n) => n.path), ['flip/growth.md']);
    c.query = 'WIENER';
    expect(c.notes.map((n) => n.path), ['lya/tomo/maps.md']);
  });

  test('concurrent syncs share one run', () async {
    remote.calls = 0;
    await Future.wait([c.sync(), c.sync(), c.sync()]);
    expect(remote.calls, 1);
  });

  test('save writes to disk before syncing; offline shows pending', () async {
    remote.failNext = const RemoteException('offline', offline: true);
    final note = parseNote('# Inbox\n- new idea\n');
    await c.saveNote('inbox.md', note);
    expect(await c.store.readNote('inbox.md'), '# Inbox\n- new idea\n');
    expect(c.status.phase, SyncPhase.offline);
    expect(c.status.pending, 1);
    await c.sync();
    expect(c.status.phase, SyncPhase.synced);
    expect(utf8.decode(remote.files()['inbox.md']!), '# Inbox\n- new idea\n');
  });

  test('saveNewNote names the file from the title, discards empty notes', () async {
    expect(await c.saveNewNote('lya', Note(title: '  ')), isNull);
    final p = await c.saveNewNote('lya', Note(title: 'P1D', lines: [const NoteLine(ItemKind.bullet, 'x')]));
    expect(p, 'lya/p1d-2.md');
    final q = await c.saveNewNote('', Note(title: '', lines: [const NoteLine(ItemKind.todo, 'Call Bob')]));
    expect(q, 'call-bob.md');
  });

  test('recent view follows opens', () async {
    await c.load('lya/tomo/maps.md');
    await c.load('inbox.md');
    c.folder = recentFolder;
    expect(c.notes.map((n) => n.path), ['inbox.md', 'lya/tomo/maps.md']);
  });

  test('moveNote renames after the title and moves folders', () async {
    final note = (await c.load('inbox.md'))!..title = 'Ideas box';
    await c.saveNote('inbox.md', note, push: false);
    final to = await c.moveNote('inbox.md', 'flip');
    expect(to, 'flip/ideas-box.md');
    expect(remote.files().containsKey('flip/ideas-box.md'), isTrue);
    expect(remote.files().containsKey('inbox.md'), isFalse);
  });

  test('deleteFolder refuses a folder with notes', () async {
    expect(await c.deleteFolder('lya'), isFalse);
    await c.createFolder('', 'empty one');
    expect(c.allFolders, contains('empty one'));
    expect(await c.deleteFolder('empty one'), isTrue);
    expect(c.allFolders, isNot(contains('empty one')));
  });

  test('no remote configured: local only', () async {
    c.remoteFactory = () => null;
    await c.sync();
    expect(c.status.phase, SyncPhase.localOnly);
  });
}
