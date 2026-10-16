import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../store/paths.dart';
import 'dialogs.dart';
import 'editor/editor_page.dart';
import 'folder_tree.dart';
import 'note_grid.dart';
import 'sync_badge.dart';
import 'theme.dart';

/// All notes: folder tree and card grid on wide screens; breadcrumbs, folder
/// tabs and cards on narrow ones.
class HomePage extends StatefulWidget {
  final AppController controller;
  final VoidCallback onSettings;

  const HomePage({super.key, required this.controller, required this.onSettings});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  AppController get c => widget.controller;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _targetFolder => c.folder == recentFolder ? '' : c.folder;

  Future<void> openNote(String? path, {String? folder}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorPage(
        controller: c,
        path: path,
        folder: folder ?? _targetFolder,
        onSettings: widget.onSettings,
      ),
    ));
  }

  void _select(String folder) {
    _search.clear();
    c.query = '';
    c.folder = folder;
  }

  Future<void> _newFolder([String? parent]) async {
    final base = parent ?? _targetFolder;
    final name = await askText(
      context,
      title: base.isEmpty ? 'New folder' : 'New folder in ${basenameOf(base)}',
      action: 'Create folder',
      hint: 'e.g. lya',
    );
    if (name == null) return;
    final path = await c.createFolder(base, name);
    if (path != null) _select(path);
  }

  Future<void> _folderMenu(String folder, Offset? at) async {
    final pos = at ?? MediaQuery.sizeOf(context).center(Offset.zero);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'new', child: Text('New subfolder…')),
        PopupMenuItem(value: 'rename', child: Text('Rename…')),
        PopupMenuItem(value: 'move', child: Text('Move to…')),
        PopupMenuItem(value: 'delete', child: Text('Delete folder')),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'new':
        await _newFolder(folder);
      case 'rename':
        final name = await askText(context, title: 'Rename folder', action: 'Rename', initial: basenameOf(folder));
        final clean = name == null ? '' : AppController.cleanFolderName(name);
        if (clean.isNotEmpty && clean != basenameOf(folder)) {
          await _guard(() => c.moveFolder(folder, joinPath(parentOf(folder), clean)));
        }
      case 'move':
        final dest = await pickFolder(context,
            folders: c.allFolders, current: parentOf(folder), exclude: {folder}, title: 'Move folder to');
        if (dest != null && dest != parentOf(folder)) {
          await _guard(() => c.moveFolder(folder, joinPath(dest, basenameOf(folder))));
        }
      case 'delete':
        if (c.countUnder(folder) > 0) {
          _snack('Move or delete the notes in ${basenameOf(folder)} first.');
        } else if (await confirm(context,
            title: 'Delete ${basenameOf(folder)}?', body: 'The folder is empty.', action: 'Delete folder')) {
          await c.deleteFolder(folder);
        }
    }
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on Exception {
      _snack('A folder or note with that name already exists there.');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => openNote(null),
        const SingleActivator(LogicalKeyboardKey.f5): c.sync,
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 700 ? _wide(context) : _narrow(context),
          ),
        ),
      ),
    );
  }

  Widget _badge({bool compact = false}) => SyncBadge(
        status: c.status,
        compact: compact,
        onSync: c.sync,
        onSettings: widget.onSettings,
      );

  Widget _searchField() => TextField(
        controller: _search,
        focusNode: _searchFocus,
        onChanged: (v) => c.query = v,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search all notes',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _search.clear();
                    c.query = '';
                  },
                ),
        ),
      );

  Widget _wide(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Row(children: [
        SizedBox(
          width: 250,
          child: FolderTree(
            controller: c,
            onSelect: _select,
            onFolderMenu: (f) => _folderMenu(f, null),
            onNewFolder: _newFolder,
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Row(children: [
                Expanded(child: Align(alignment: Alignment.centerLeft, child: _badge())),
                IconButton(
                  tooltip: 'Settings',
                  icon: Icon(Icons.settings_outlined, color: p.muted),
                  onPressed: widget.onSettings,
                ),
              ]),
            ),
          ),
        ),
        VerticalDivider(width: 1, color: p.border),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
              child: Row(children: [
                Expanded(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _searchField())),
                const SizedBox(width: 12),
                IconButton(tooltip: 'Sync now (F5)', onPressed: c.sync, icon: const Icon(Icons.sync)),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () => openNote(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New note'),
                ),
              ]),
            ),
            _heading(p, pad: 24),
            Expanded(child: _grid(context)),
          ]),
        ),
      ]),
    );
  }

  Widget _narrow(BuildContext context) {
    final p = context.palette;
    return PopScope(
      canPop: c.folder.isEmpty && c.query.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (c.query.isNotEmpty) {
          _search.clear();
          c.query = '';
        } else if (c.folder == recentFolder) {
          c.folder = '';
        } else {
          c.folder = parentOf(c.folder);
        }
      },
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          tooltip: 'New note',
          onPressed: () => openNote(null),
          child: const Icon(Icons.add),
        ),
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
              child: Row(children: [
                Expanded(child: _searchField()),
                _badge(compact: true),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: Icon(Icons.more_vert, color: p.ink),
                  onSelected: (v) => switch (v) {
                    'recent' => _select(recentFolder),
                    'folder' => _newFolder(),
                    'settings' => widget.onSettings(),
                    _ => null,
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'recent', child: Text('Recent notes')),
                    PopupMenuItem(value: 'folder', child: Text('New folder…')),
                    PopupMenuItem(value: 'settings', child: Text('Settings')),
                  ],
                ),
              ]),
            ),
            _heading(p, pad: 12),
            Expanded(child: _grid(context)),
          ]),
        ),
      ),
    );
  }

  /// Breadcrumbs above the current folder's name, set large.
  Widget _heading(Palette p, {required double pad}) {
    final crumbs = <(String, String)>[];
    String title;
    String? sub;
    if (c.query.trim().isNotEmpty) {
      title = 'Search';
      final n = c.notes.length;
      sub = n == 0 ? 'No matches' : '$n match${n > 1 ? 'es' : ''}';
    } else if (c.folder == recentFolder) {
      title = 'Recent';
      sub = 'Opened on this device';
    } else if (c.folder.isEmpty) {
      title = 'Notes';
    } else {
      final parts = c.folder.split('/');
      crumbs.add(('Notes', ''));
      for (var i = 0; i < parts.length - 1; i++) {
        crumbs.add((parts[i], parts.sublist(0, i + 1).join('/')));
      }
      title = parts.last;
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (crumbs.isNotEmpty)
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final (label, path) in crumbs) ...[
              InkWell(
                onTap: () => _select(path),
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Text(label, style: TextStyle(fontSize: 14, color: p.muted, decoration: TextDecoration.underline, decorationColor: p.border)),
                ),
              ),
              Text('  /  ', style: TextStyle(fontSize: 14, color: p.muted)),
            ],
          ]),
        Text(title, style: titleText(p, size: 32).copyWith(height: 1.15)),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(sub, style: TextStyle(fontSize: 14, color: p.muted)),
          ),
      ]),
    );
  }

  Widget _grid(BuildContext context) {
    final p = context.palette;
    final searching = c.query.trim().isNotEmpty;
    final String emptyText;
    if (searching) {
      emptyText = 'Nothing matches “${c.query.trim()}”.';
    } else if (c.folder == recentFolder) {
      emptyText = 'Notes you open on this device appear here.';
    } else {
      emptyText = 'No notes here yet. Press + to start one.';
    }
    return NoteGrid(
      controller: c,
      folders: c.subfolders,
      notes: c.notes,
      showFolders: searching || c.folder == recentFolder,
      onOpenFolder: _select,
      onOpenNote: (path) => openNote(path),
      onFolderMenu: (f) => _folderMenu(f, null),
      empty: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Text(emptyText, style: noteText(p, size: 16, color: p.muted)),
      ),
    );
  }
}
