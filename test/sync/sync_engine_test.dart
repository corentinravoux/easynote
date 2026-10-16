import 'dart:convert';
import 'dart:io';

import 'package:easynote/store/local_store.dart';
import 'package:easynote/sync/fake_remote.dart';
import 'package:easynote/sync/remote_repo.dart';
import 'package:easynote/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> b(String s) => utf8.encode(s);
String s(List<int>? b) => b == null ? '<none>' : utf8.decode(b);

void main() {
  late Directory tmp;
  late FakeRemote remote;
  var n = 0;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('easynote_sync_');
    remote = FakeRemote({'README.md': b('repo readme\n')});
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<SyncEngine> device(String name) async {
    final id = n++;
    final store = await LocalStore.open(
        Directory('${tmp.path}/$id/notes'), File('${tmp.path}/$id/state.json'));
    return SyncEngine(store, remote,
        device: name, clock: () => DateTime(2026, 10, 16, 12, 5));
  }

  Future<String> local(SyncEngine e, String path) async =>
      s(await e.store.readBytes(path));
  String remoteText(String path) => s(remote.files()[path]);

  group('first sync', () {
    test('downloads every tracked file, ignores untracked ones', () async {
      remote.externalCommit({
        'lya/p1d.md': b('# P1D\n'),
        'lya/.keep': [],
        '.github/x.md': b('ci\n'),
        'image.png': [1, 2, 3],
      });
      final e = await device('laptop');
      final r = await e.sync();
      expect(r.error, isNull);
      expect(await e.store.notePaths(), ['lya/p1d.md']);
      expect(await e.store.readBytes('lya/.keep'), isEmpty);
      expect(await e.store.readBytes('README.md'), isNull);
      expect(r.downloaded, 2);
    });
  });

  group('decision table', () {
    late SyncEngine e;
    setUp(() async {
      remote.externalCommit({'a.md': b('# A\n- one\n')});
      e = await device('laptop');
      await e.sync();
    });

    test('nothing changed: one API call, no commit', () async {
      final head = remote.head;
      remote.calls = 0;
      final r = await e.sync();
      expect(remote.calls, 1);
      expect(remote.head, head);
      expect(r.pushed, 0);
    });

    test('remote changed, local same: download', () async {
      remote.externalCommit({'a.md': b('# A\n- two\n')});
      await e.sync();
      expect(await local(e, 'a.md'), '# A\n- two\n');
    });

    test('local changed, remote same: push', () async {
      await e.store.writeBytes('a.md', b('# A\n- mine\n'));
      final r = await e.sync();
      expect(r.pushed, 1);
      expect(remoteText('a.md'), '# A\n- mine\n');
      expect(remote.lastMessage, 'easynote: laptop: edit a.md');
      expect(await e.pendingCount(), 0);
    });

    test('both changed to the same content: no conflict, no push', () async {
      remote.externalCommit({'a.md': b('# A\n- same\n')});
      await e.store.writeBytes('a.md', b('# A\n- same\n'));
      final r = await e.sync();
      expect(r.conflicts, isEmpty);
      expect(r.pushed, 0);
    });

    test('both changed differently: conflict copy, nothing lost', () async {
      remote.externalCommit({'a.md': b('# A\n- theirs\n')});
      await e.store.writeBytes('a.md', b('# A\n- mine\n'));
      final r = await e.sync();
      const copy = 'a.conflict-laptop-20261016-1205.md';
      expect(r.conflicts, [copy]);
      expect(await local(e, 'a.md'), '# A\n- theirs\n');
      expect(await local(e, copy), '# A (conflict)\n- mine\n');
      expect(remoteText(copy), '# A (conflict)\n- mine\n');
      expect(remoteText('a.md'), '# A\n- theirs\n');
    });

    test('remote deleted, local same: delete local', () async {
      remote.externalCommit({'a.md': null});
      final r = await e.sync();
      expect(await e.store.readBytes('a.md'), isNull);
      expect(r.deleted, 1);
    });

    test('remote deleted, local edited: edit survives and is re-created', () async {
      remote.externalCommit({'a.md': null});
      await e.store.writeBytes('a.md', b('# A\n- keep me\n'));
      await e.sync();
      expect(await local(e, 'a.md'), '# A\n- keep me\n');
      expect(remoteText('a.md'), '# A\n- keep me\n');
    });

    test('local deleted, remote same: delete pushed', () async {
      await e.store.delete('a.md');
      await e.sync();
      expect(remote.files().containsKey('a.md'), isFalse);
      expect(remote.lastMessage, 'easynote: laptop: delete a.md');
    });

    test('local deleted, remote edited: remote edit restored', () async {
      await e.store.delete('a.md');
      remote.externalCommit({'a.md': b('# A\n- edited elsewhere\n')});
      await e.sync();
      expect(await local(e, 'a.md'), '# A\n- edited elsewhere\n');
      expect(remoteText('a.md'), '# A\n- edited elsewhere\n');
    });

    test('new local file: pushed as add', () async {
      await e.store.writeBytes('lya/new.md', b('# New\n'));
      await e.sync();
      expect(remoteText('lya/new.md'), '# New\n');
      expect(remote.lastMessage, 'easynote: laptop: add lya/new.md');
    });

    test('new remote file: downloaded', () async {
      remote.externalCommit({'flip/g.md': b('# G\n')});
      await e.sync();
      expect(await local(e, 'flip/g.md'), '# G\n');
    });
  });

  test('two devices create the same path offline: conflict, both kept', () async {
    // Review focus 2.
    final laptop = await device('laptop');
    final phone = await device('phone');
    await laptop.sync();
    await phone.sync();
    await laptop.store.writeBytes('idea.md', b('# Idea\n- from laptop\n'));
    await phone.store.writeBytes('idea.md', b('# Idea\n- from phone\n'));
    await laptop.sync();
    final r = await phone.sync();
    expect(r.conflicts, ['idea.conflict-phone-20261016-1205.md']);
    final texts = remote.files().values.map(s).join();
    expect(texts, contains('from laptop'));
    expect(texts, contains('from phone'));
  });

  test('delete on one device, edit on the other: edit survives both ways', () async {
    // Review focus 3.
    remote.externalCommit({'x.md': b('# X\n'), 'y.md': b('# Y\n')});
    final laptop = await device('laptop');
    final phone = await device('phone');
    await laptop.sync();
    await phone.sync();
    await laptop.store.delete('x.md');
    await phone.store.writeBytes('x.md', b('# X\n- phone edit\n'));
    await phone.store.delete('y.md');
    await laptop.store.writeBytes('y.md', b('# Y\n- laptop edit\n'));
    await laptop.sync();
    await phone.sync();
    await laptop.sync();
    for (final d in [laptop, phone]) {
      expect(await local(d, 'x.md'), '# X\n- phone edit\n');
      expect(await local(d, 'y.md'), '# Y\n- laptop edit\n');
    }
  });

  test('non-fast-forward: pull and retry once', () async {
    final e = await device('laptop');
    await e.sync();
    await e.store.writeBytes('mine.md', b('# Mine\n'));
    var injected = false;
    remote.beforeCommit = () {
      if (!injected) {
        injected = true;
        remote.externalCommit({'theirs.md': b('# Theirs\n')});
      }
    };
    final r = await e.sync();
    expect(r.error, isNull);
    expect(remote.files().keys, containsAll(['mine.md', 'theirs.md']));
    expect(await local(e, 'theirs.md'), '# Theirs\n');
  });

  test('non-fast-forward twice: error, changes still pending', () async {
    final e = await device('laptop');
    await e.sync();
    await e.store.writeBytes('mine.md', b('# Mine\n'));
    var i = 0;
    remote.beforeCommit = () => remote.externalCommit({'t${i++}.md': b('t\n')});
    final r = await e.sync();
    expect(r.error, contains('pending'));
    expect(await e.pendingCount(), 1);
  });

  test('offline: local edits stay pending and push later', () async {
    final e = await device('laptop');
    await e.sync();
    await e.store.writeBytes('a.md', b('# A\n'));
    remote.failNext = const RemoteException('offline', offline: true);
    final r = await e.sync();
    expect(r.offline, isTrue);
    expect(await e.pendingCount(), 1);
    final r2 = await e.sync();
    expect(r2.error, isNull);
    expect(remoteText('a.md'), '# A\n');
  });

  test('auth error is reported and loses nothing', () async {
    // Review focus 5.
    final e = await device('laptop');
    await e.sync();
    await e.store.writeBytes('a.md', b('# A\n'));
    remote.failNext = const AuthException(401);
    final r = await e.sync();
    expect(r.authError, isTrue);
    expect(await local(e, 'a.md'), '# A\n');
    expect(await e.pendingCount(), 1);
  });

  test('folder move is one atomic commit', () async {
    remote.externalCommit({
      'lya/p1d.md': b('# P1D\n'),
      'lya/tomo/maps.md': b('# Maps\n'),
      'lya/.keep': [],
    });
    final e = await device('laptop');
    await e.sync();
    final before = remote.head;
    await e.store.move('lya', 'archive/lya');
    final r = await e.sync();
    expect(r.pushed, 6);
    expect(remote.lastMessage, 'easynote: laptop: 6 changes');
    expect(remote.files().keys.where((p) => p.startsWith('lya/')), isEmpty);
    expect(remote.files().keys,
        containsAll(['archive/lya/p1d.md', 'archive/lya/tomo/maps.md', 'archive/lya/.keep']));
    expect(remote.head, isNot(before));
  });

  test('untracked remote files survive pushes', () async {
    final e = await device('laptop');
    await e.sync();
    await e.store.writeBytes('a.md', b('# A\n'));
    await e.sync();
    expect(remoteText('README.md'), 'repo readme\n');
  });

  test('a second conflict in the same minute gets a distinct name', () async {
    remote.externalCommit({'a.md': b('# A\n')});
    final e = await device('lap top');
    await e.sync();
    for (final v in ['1', '2']) {
      remote.externalCommit({'a.md': b('# A\n- theirs $v\n')});
      await e.store.writeBytes('a.md', b('# A\n- mine $v\n'));
      await e.sync();
    }
    final copies = (await e.store.notePaths()).where((p) => p.contains('.conflict-'));
    expect(copies, ['a.conflict-lap-top-20261016-1205-2.md', 'a.conflict-lap-top-20261016-1205.md']);
  });
}
