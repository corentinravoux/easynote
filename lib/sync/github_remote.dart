import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../store/blob_sha.dart';
import 'remote_repo.dart';

/// [RemoteRepo] over the GitHub Git Data API (refs, trees, blobs, commits).
///
/// Needs a fine-grained token with Contents read/write on the one repo.
class GithubRemote implements RemoteRepo {
  final String owner, repo, branch, token;
  final http.Client _client;
  final Duration timeout;

  GithubRemote({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  Uri _uri(String path) =>
      Uri.parse('https://api.github.com/repos/$owner/$repo$path');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      };

  Future<dynamic> _send(String method, String path,
      {Object? body, bool isRefUpdate = false}) async {
    final req = http.Request(method, _uri(path))..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(
          await _client.send(req).timeout(timeout));
    } on TimeoutException {
      throw const RemoteException('offline', offline: true);
    } on SocketException {
      throw const RemoteException('offline', offline: true);
    } on http.ClientException {
      throw const RemoteException('offline', offline: true);
    }
    final s = res.statusCode;
    if (s >= 200 && s < 300) return jsonDecode(res.body);
    if (s == 403 && res.headers['x-ratelimit-remaining'] == '0') {
      throw const RemoteException('rate limited by GitHub, try again later');
    }
    if (s == 401 || s == 403) throw AuthException(s);
    if (isRefUpdate && s == 422) throw const NonFastForwardException();
    if (s == 409 && res.body.contains('empty')) {
      throw const RemoteException(
          'repository is empty: add a README on github.com first');
    }
    if (s == 404) {
      throw RemoteException('not found: check owner, repo and branch ($path)');
    }
    throw RemoteException('GitHub answered HTTP $s on $method $path');
  }

  @override
  Future<String> headSha() async =>
      (await _send('GET', '/git/ref/heads/$branch'))['object']['sha'] as String;

  @override
  Future<Map<String, String>> tree(String commitSha) async {
    final j = await _send('GET', '/git/trees/$commitSha?recursive=1');
    if (j['truncated'] == true) {
      throw const RemoteException('repository tree too large to list');
    }
    return {
      for (final e in j['tree'] as List)
        if (e['type'] == 'blob') e['path'] as String: e['sha'] as String,
    };
  }

  @override
  Future<List<int>> blob(String sha) async {
    final j = await _send('GET', '/git/blobs/$sha');
    final content = (j['content'] as String).replaceAll(RegExp(r'\s'), '');
    return base64.decode(content);
  }

  @override
  Future<String> commit({
    required String parent,
    required Map<String, List<int>?> changes,
    required String message,
  }) async {
    final parentTree =
        (await _send('GET', '/git/commits/$parent'))['tree']['sha'] as String;
    final entries = <Map<String, dynamic>>[];
    for (final e in changes.entries) {
      String? sha;
      final bytes = e.value;
      if (bytes != null) {
        final j = await _send('POST', '/git/blobs',
            body: {'content': base64.encode(bytes), 'encoding': 'base64'});
        sha = j['sha'] as String;
        assert(sha == gitBlobSha(bytes));
      }
      entries.add(
          {'path': e.key, 'mode': '100644', 'type': 'blob', 'sha': sha});
    }
    final tree = await _send('POST', '/git/trees',
        body: {'base_tree': parentTree, 'tree': entries});
    final commit = await _send('POST', '/git/commits', body: {
      'message': message,
      'tree': tree['sha'],
      'parents': [parent],
    });
    final sha = commit['sha'] as String;
    await _send('PATCH', '/git/refs/heads/$branch',
        body: {'sha': sha, 'force': false}, isRefUpdate: true);
    return sha;
  }
}
