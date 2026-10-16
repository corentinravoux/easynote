import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Non-secret settings, stored as JSON next to the app data. The token is
/// not here: it lives in [TokenStore].
class Settings {
  String owner;
  String repo;
  String branch;
  String device;
  bool eink;

  /// Desktop only: where the note files live. Null means the default inside
  /// the app's data directory.
  String? notesDir;

  Settings({
    this.owner = '',
    this.repo = '',
    this.branch = 'main',
    this.device = '',
    this.eink = false,
    this.notesDir,
  });

  bool get configured => owner.isNotEmpty && repo.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'device': device,
        'eink': eink,
        'notesDir': notesDir,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        owner: j['owner'] as String? ?? '',
        repo: j['repo'] as String? ?? '',
        branch: j['branch'] as String? ?? 'main',
        device: j['device'] as String? ?? '',
        eink: j['eink'] as bool? ?? false,
        notesDir: j['notesDir'] as String?,
      );

  static Future<Settings> load(File f) async {
    if (!await f.exists()) return Settings();
    try {
      return Settings.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } on FormatException {
      return Settings();
    }
  }

  Future<void> save(File f) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
    await tmp.rename(f.path);
  }
}

/// The GitHub token, kept in the platform keychain (GNOME Keyring through
/// libsecret on Linux, the Keystore on Android). Never written to a file.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'github_token';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? token) => token == null || token.isEmpty
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: token);
}

class MemoryTokenStore implements TokenStore {
  String? token;
  MemoryTokenStore([this.token]);
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String? t) async => token = t;
}
