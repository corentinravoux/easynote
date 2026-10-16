import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/controller.dart';
import 'app/settings.dart';
import 'platform/widget_bridge.dart';
import 'store/local_store.dart';
import 'sync/github_remote.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dataDir = await getApplicationSupportDirectory();
  final settingsFile = File('${dataDir.path}/settings.json');
  final settings = await Settings.load(settingsFile);
  if (settings.device.isEmpty) {
    settings.device = Platform.isAndroid ? 'android' : Platform.localHostname;
  }
  final defaultNotes = '${dataDir.path}/notes';
  final store = await LocalStore.open(
    Directory(settings.notesDir ?? defaultNotes),
    File('${dataDir.path}/sync_state.json'),
  );
  final tokens = SecureTokenStore();
  String? token;
  try {
    token = await tokens.read();
  } on Exception {
    token = null;
  }
  runApp(EasyNoteApp(
    store: store,
    settings: settings,
    settingsFile: settingsFile,
    tokens: tokens,
    initialToken: token,
    defaultNotesPath: defaultNotes,
  ));
}

class EasyNoteApp extends StatefulWidget {
  final LocalStore store;
  final Settings settings;
  final File settingsFile;
  final TokenStore tokens;
  final String? initialToken;
  final String defaultNotesPath;

  const EasyNoteApp({
    super.key,
    required this.store,
    required this.settings,
    required this.settingsFile,
    required this.tokens,
    required this.initialToken,
    required this.defaultNotesPath,
  });

  @override
  State<EasyNoteApp> createState() => _EasyNoteAppState();
}

class _EasyNoteAppState extends State<EasyNoteApp> {
  final _nav = GlobalKey<NavigatorState>();
  final _home = GlobalKey<HomePageState>();
  final _bridge = WidgetBridge();
  late Settings _settings = widget.settings;
  late String? _token = widget.initialToken;
  late final AppController _c;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<Uri>? _launches;

  @override
  void initState() {
    super.initState();
    _c = AppController(store: widget.store, remoteFactory: _remote, device: _settings.device);
    _c.addListener(() => _bridge.update(_c.recent()));
    _lifecycle = AppLifecycleListener(
      onResume: Platform.isAndroid ? _c.sync : null,
      onExitRequested: _beforeExit,
    );
    _c.reload().then((_) {
      // Widget taps are handled once the notes are loaded, so a cold start
      // from the widget can open the note it names.
      _launches = _bridge.launches().listen(_onLaunch);
      _c.sync();
      if (!_settings.configured) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings());
      }
    });
  }

  GithubRemote? _remote() {
    final t = _token;
    if (!_settings.configured || t == null || t.isEmpty) return null;
    return GithubRemote(owner: _settings.owner, repo: _settings.repo, branch: _settings.branch, token: t);
  }

  Future<AppExitResponse> _beforeExit() async {
    try {
      final flush = _c.flushEditor;
      await (flush != null ? flush() : _c.sync()).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Unsynced edits are on disk and go out at the next start.
    }
    return AppExitResponse.exit;
  }

  void _onLaunch(Uri uri) {
    final home = _home.currentState;
    if (home == null) return;
    _nav.currentState?.popUntil((r) => r.isFirst);
    if (uri.host == 'open') {
      final path = uri.queryParameters['path'];
      if (path != null && _c.summary(path) != null) home.openNote(path);
    } else if (uri.host == 'new') {
      home.openNote(null, folder: '');
    }
  }

  Future<void> _openSettings() async {
    await _nav.currentState?.push(MaterialPageRoute(
      builder: (_) => SettingsPage(
        settings: _settings,
        tokens: widget.tokens,
        notesPath: widget.defaultNotesPath,
        onSave: _saveSettings,
      ),
    ));
  }

  Future<void> _saveSettings(Settings s, String? token) async {
    if (token != null) {
      await widget.tokens.write(token);
      _token = token;
    }
    if (s.device.isEmpty) s.device = _settings.device;
    await s.save(widget.settingsFile);
    setState(() => _settings = s);
    _c.device = s.device;
    await _c.sync();
  }

  @override
  void dispose() {
    _launches?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _nav,
      title: 'easynote',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(_settings.eink ? Palette.eink : Palette.light, Brightness.light),
      darkTheme: buildTheme(_settings.eink ? Palette.eink : Palette.dark, _settings.eink ? Brightness.light : Brightness.dark),
      home: HomePage(key: _home, controller: _c, onSettings: _openSettings),
    );
  }
}
