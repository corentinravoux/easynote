import 'dart:convert';
import 'dart:io';

import 'package:easynote/store/blob_sha.dart';
import 'package:easynote/sync/github_remote.dart';
import 'package:easynote/sync/remote_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const api = 'https://api.github.com/repos/o/r';

GithubRemote remoteWith(MockClientHandler h) => GithubRemote(
    owner: 'o', repo: 'r', branch: 'main', token: 'tok', client: MockClient(h));

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  test('headSha reads the ref and sends auth headers', () async {
    late http.Request seen;
    final r = remoteWith((req) async {
      seen = req;
      return json({'object': {'sha': 'abc'}});
    });
    expect(await r.headSha(), 'abc');
    expect(seen.url.toString(), '$api/git/ref/heads/main');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.headers['X-GitHub-Api-Version'], '2022-11-28');
  });

  test('tree keeps blobs only', () async {
    final r = remoteWith((req) async {
      expect(req.url.toString(), '$api/git/trees/c1?recursive=1');
      return json({
        'truncated': false,
        'tree': [
          {'path': 'lya', 'type': 'tree', 'sha': 't'},
          {'path': 'lya/a.md', 'type': 'blob', 'sha': 's1'},
        ],
      });
    });
    expect(await r.tree('c1'), {'lya/a.md': 's1'});
  });

  test('truncated tree is an error', () async {
    final r = remoteWith((_) async => json({'truncated': true, 'tree': []}));
    expect(r.tree('c'), throwsA(isA<RemoteException>()));
  });

  test('blob decodes base64 with embedded newlines', () async {
    final enc = base64.encode(utf8.encode('# Lyα\n- a long line\n'));
    final wrapped = '${enc.substring(0, 10)}\n${enc.substring(10)}\n';
    final r = remoteWith((_) async => json({'content': wrapped, 'encoding': 'base64'}));
    expect(utf8.decode(await r.blob('s')), '# Lyα\n- a long line\n');
  });

  test('commit: blob, tree with deletion, commit, fast-forward ref', () async {
    final calls = <String>[];
    final bodies = <String, dynamic>{};
    final added = utf8.encode('# New\n');
    final r = remoteWith((req) async {
      final key = '${req.method} ${req.url.path.replaceFirst('/repos/o/r', '')}';
      calls.add(key);
      if (req.body.isNotEmpty) bodies[key] = jsonDecode(req.body);
      return switch (key) {
        'GET /git/commits/p1' => json({'tree': {'sha': 'pt'}}),
        'POST /git/blobs' => json({'sha': gitBlobSha(added)}, 201),
        'POST /git/trees' => json({'sha': 'nt'}, 201),
        'POST /git/commits' => json({'sha': 'c2'}, 201),
        'PATCH /git/refs/heads/main' => json({'object': {'sha': 'c2'}}),
        _ => throw StateError('unexpected $key'),
      };
    });
    final sha = await r.commit(
        parent: 'p1', changes: {'new.md': added, 'old.md': null}, message: 'm');
    expect(sha, 'c2');
    expect(calls, [
      'GET /git/commits/p1',
      'POST /git/blobs',
      'POST /git/trees',
      'POST /git/commits',
      'PATCH /git/refs/heads/main',
    ]);
    expect(bodies['POST /git/blobs'], {'content': base64.encode(added), 'encoding': 'base64'});
    expect(bodies['POST /git/trees'], {
      'base_tree': 'pt',
      'tree': [
        {'path': 'new.md', 'mode': '100644', 'type': 'blob', 'sha': gitBlobSha(added)},
        {'path': 'old.md', 'mode': '100644', 'type': 'blob', 'sha': null},
      ],
    });
    expect(bodies['POST /git/commits'], {'message': 'm', 'tree': 'nt', 'parents': ['p1']});
    expect(bodies['PATCH /git/refs/heads/main'], {'sha': 'c2', 'force': false});
  });

  test('other 422s on the ref update are plain errors', () async {
    final r = remoteWith((req) async => req.method == 'PATCH'
        ? json({'message': 'Reference does not exist'}, 422)
        : json({'sha': 'x', 'tree': {'sha': 't'}}, 201));
    expect(r.commit(parent: 'p', changes: {'a.md': null}, message: 'm'),
        throwsA(isA<RemoteException>()));
  });

  test('ref update 422 is non-fast-forward', () async {
    final r = remoteWith((req) async => req.method == 'PATCH'
        ? json({'message': 'Update is not a fast forward'}, 422)
        : json({'sha': 'x', 'tree': {'sha': 't'}}, 201));
    expect(r.commit(parent: 'p', changes: {'a.md': null}, message: 'm'),
        throwsA(isA<NonFastForwardException>()));
  });

  group('status mapping', () {
    test('401 and 403 are auth errors', () async {
      for (final s in [401, 403]) {
        final r = remoteWith((_) async => json({'message': 'Bad credentials'}, s));
        await expectLater(r.headSha(), throwsA(isA<AuthException>()));
      }
    });
    test('403 with exhausted rate limit is not an auth error', () async {
      final r = remoteWith((_) async => http.Response('{}', 403,
          headers: {'x-ratelimit-remaining': '0'}));
      await expectLater(r.headSha(),
          throwsA(isA<RemoteException>().having((e) => e.message, 'm', contains('rate'))));
    });
    test('secondary rate limit (403 with retry-after, or 429) is not an auth error', () async {
      for (final res in [
        http.Response('{}', 403, headers: {'retry-after': '60'}),
        http.Response('{}', 429),
      ]) {
        final r = remoteWith((_) async => res);
        await expectLater(r.headSha(),
            throwsA(isA<RemoteException>().having((e) => e.message, 'm', contains('rate'))));
      }
    });
    test('a non-JSON success page (captive portal) is a remote error', () async {
      final r = remoteWith((_) async => http.Response('<html>login</html>', 200));
      await expectLater(r.headSha(), throwsA(isA<RemoteException>()));
    });
    test('TLS failure is offline', () async {
      final r = remoteWith((_) async => throw const HandshakeException('bad cert'));
      await expectLater(r.headSha(),
          throwsA(isA<RemoteException>().having((e) => e.offline, 'offline', isTrue)));
    });
    test('409 on empty repo explains itself', () async {
      final r = remoteWith((_) async => json({'message': 'Git Repository is empty.'}, 409));
      await expectLater(r.headSha(),
          throwsA(isA<RemoteException>().having((e) => e.message, 'm', contains('empty'))));
    });
    test('404 names the settings to check', () async {
      final r = remoteWith((_) async => json({'message': 'Not Found'}, 404));
      await expectLater(r.headSha(),
          throwsA(isA<RemoteException>().having((e) => e.message, 'm', contains('owner'))));
    });
    test('socket failure is offline', () async {
      final r = remoteWith((_) async => throw const SocketException('no route'));
      await expectLater(r.headSha(),
          throwsA(isA<RemoteException>().having((e) => e.offline, 'offline', isTrue)));
    });
  });
}
