import 'dart:io';

import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../sync/github_remote.dart';
import '../sync/remote_repo.dart';
import 'theme.dart';

/// Where notes sync to, this device's name, and display options.
class SettingsPage extends StatefulWidget {
  final Settings settings;
  final TokenStore tokens;
  final String notesPath;
  final Future<void> Function(Settings settings, String? token) onSave;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.tokens,
    required this.notesPath,
    required this.onSave,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _owner = TextEditingController(text: widget.settings.owner);
  late final _repo = TextEditingController(text: widget.settings.repo);
  late final _branch = TextEditingController(text: widget.settings.branch);
  late final _device = TextEditingController(text: widget.settings.device);
  late final _notesDir = TextEditingController(text: widget.settings.notesDir ?? '');
  final _token = TextEditingController();
  late bool _eink = widget.settings.eink;
  bool _hasToken = false;
  bool _showToken = false;
  String? _test;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    widget.tokens.read().then((t) {
      if (mounted) setState(() => _hasToken = t != null && t.isNotEmpty);
    });
  }

  Settings _collect() => Settings(
        owner: _owner.text.trim(),
        repo: _repo.text.trim(),
        branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
        device: _device.text.trim(),
        eink: _eink,
        notesDir: _notesDir.text.trim().isEmpty ? null : _notesDir.text.trim(),
      );

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final s = _collect();
    final token = _token.text.trim().isNotEmpty ? _token.text.trim() : await widget.tokens.read();
    String result;
    if (!s.configured || token == null || token.isEmpty) {
      result = 'Fill in owner, repository and token first.';
    } else {
      try {
        await GithubRemote(owner: s.owner, repo: s.repo, branch: s.branch, token: token).headSha();
        result = 'Connected. ${s.owner}/${s.repo} on ${s.branch} is reachable.';
      } on AuthException {
        result = 'GitHub refused the token. Check that it has Contents read and write on this repository.';
      } on RemoteException catch (e) {
        result = e.offline ? 'No connection to GitHub.' : e.message;
      }
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _test = result;
      });
    }
  }

  Future<void> _save() async {
    final token = _token.text.trim();
    try {
      await widget.onSave(_collect(), token.isEmpty ? null : token);
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not store the token in the system keyring: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget field(String label, TextEditingController ctrl, {String? hint, String? help, bool obscure = false, Widget? suffix}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.ink)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
            ),
            if (help != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(help, style: TextStyle(fontSize: 13, color: p.muted, height: 1.35)),
              ),
          ]),
        );

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: titleText(p, size: 20)),
            const SizedBox(height: 4),
            Container(height: 1.5, width: 48, color: p.accent),
            const SizedBox(height: 16),
            ...children,
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.desk,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.ink,
        title: Text('Settings', style: titleText(p, size: 20)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _save, child: const Text('Save settings')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                section('GitHub repository', [
                  Text(
                    'Notes sync to one private repository when the app opens and when you close a note. '
                    'Create the repository on github.com with a README, then a fine-grained token limited to it, '
                    'with the Contents permission set to read and write.',
                    style: TextStyle(fontSize: 14, color: p.muted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  field('Owner', _owner, hint: 'your GitHub user name'),
                  field('Repository', _repo, hint: 'the private notes repository'),
                  field('Branch', _branch, hint: 'main'),
                  field(
                    'Token',
                    _token,
                    obscure: !_showToken,
                    hint: _hasToken ? 'Stored in the keyring. Paste a new one to replace it.' : 'github_pat_…',
                    help: 'Kept in the system keyring, never in a file.',
                    suffix: IconButton(
                      tooltip: _showToken ? 'Hide token' : 'Show token',
                      icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                      onPressed: () => setState(() => _showToken = !_showToken),
                    ),
                  ),
                  Row(children: [
                    OutlinedButton(
                      onPressed: _testing ? null : _testConnection,
                      child: Text(_testing ? 'Testing…' : 'Test connection'),
                    ),
                  ]),
                  if (_test != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_test!, style: TextStyle(fontSize: 14, color: p.ink, height: 1.35)),
                    ),
                ]),
                section('This device', [
                  field('Device name', _device,
                      hint: Platform.isAndroid ? 'phone' : 'laptop',
                      help: 'Appears in commit messages and in the names of conflict copies.'),
                  if (!Platform.isAndroid)
                    field('Notes folder', _notesDir,
                        hint: widget.notesPath,
                        help: 'Where the note files live on this computer. Takes effect after a restart.'),
                ]),
                section('Display', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _eink,
                    onChanged: (v) => setState(() => _eink = v),
                    title: Text('E-ink mode', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                    subtitle: Text('Black on white, no animations. For e-ink tablets.',
                        style: TextStyle(color: p.muted)),
                  ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
