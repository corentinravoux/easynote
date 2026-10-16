import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../format/note.dart';
import '../../store/paths.dart';
import '../dialogs.dart';
import '../sync_badge.dart';
import '../theme.dart';
import 'editor_model.dart';
import 'item_row.dart';

/// Edit one note. Typing is written to disk after a second of rest; closing
/// the editor, Ctrl+S, or the app going to background saves and syncs.
class EditorPage extends StatefulWidget {
  final AppController controller;

  /// Null for a note that has no file yet.
  final String? path;

  /// Folder a new note is created in.
  final String folder;
  final VoidCallback onSettings;

  const EditorPage({
    super.key,
    required this.controller,
    required this.path,
    required this.folder,
    required this.onSettings,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _Row {
  final TextEditingController text;
  final FocusNode focus;
  _Row(String t) : text = TextEditingController(text: t), focus = FocusNode();
  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

class _EditorPageState extends State<EditorPage> {
  AppController get c => widget.controller;

  String? _path;
  Note? _original;
  bool _loading = true;
  final _title = TextEditingController();
  final _titleFocus = FocusNode();
  late EditorModel _model;
  List<_Row> _rows = [];
  int _current = 0;

  bool _dirty = false;
  bool _savedLocally = false;
  bool _closed = false;
  Timer? _debounce;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _path = widget.path;
    _lifecycle = AppLifecycleListener(onHide: _flush, onPause: _flush);
    c.flushEditor = _flush;
    _load();
  }

  Future<void> _load() async {
    final path = _path;
    Note note;
    if (path != null) {
      note = await c.load(path) ?? Note(title: '');
      _original = note;
    } else {
      note = Note(title: '');
    }
    _title.text = note.title;
    _model = EditorModel(note.lines);
    _rebuildRows();
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (path == null) {
        _titleFocus.requestFocus();
      } else if (note.lines.isEmpty) {
        _rows.first.focus.requestFocus();
      }
    });
  }

  void _rebuildRows({Focus2? focus}) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows = [for (final l in _model.lines) _Row(l.text)];
    for (var i = 0; i < _rows.length; i++) {
      final idx = i;
      _rows[i].focus.addListener(() {
        if (_rows.length > idx && _rows[idx].focus.hasFocus) _current = idx;
      });
    }
    if (focus != null) {
      _current = focus.index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || focus.index >= _rows.length) return;
        final r = _rows[focus.index];
        r.focus.requestFocus();
        r.text.selection = TextSelection.collapsed(offset: focus.caret.clamp(0, r.text.text.length));
      });
    }
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => _save(push: false));
  }

  void _structural(Focus2? f) {
    if (f == null) return;
    setState(() => _rebuildRows(focus: f));
    _changed();
  }

  int _caret(int i) => _rows[i].text.selection.baseOffset.clamp(0, _rows[i].text.text.length);

  Note _currentNote() {
    final o = _original;
    final title = _title.text.trim();
    return Note(
      title: title,
      lines: _model.saved,
      hasTitleLine: (o?.hasTitleLine ?? true) || title.isNotEmpty,
      trailingNewline: o?.trailingNewline ?? true,
    );
  }

  Future<void> _save({required bool push}) async {
    _debounce?.cancel();
    if (!_dirty) {
      if (push && _savedLocally) {
        _savedLocally = false;
        await c.sync();
      }
      return;
    }
    _dirty = false;
    final note = _currentNote();
    if (_path == null) {
      _path = await c.saveNewNote(widget.folder, note, push: push);
    } else {
      await c.saveNote(_path!, note, push: push);
    }
    _savedLocally = !push && _path != null;
  }

  Future<void> _flush() => _save(push: true);

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    await _flush();
  }

  @override
  void dispose() {
    if (c.flushEditor == _flush) c.flushEditor = null;
    _debounce?.cancel();
    _lifecycle.dispose();
    _title.dispose();
    _titleFocus.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  RowKeys _keys(int i) => RowKeys(
        onEnter: () => _structural(_model.enter(i, _caret(i))),
        onBackspaceAtStart: () {
          if (i == 0 && _rows[0].text.text.isEmpty) {
            _titleFocus.requestFocus();
            return;
          }
          _structural(_model.backspaceAtStart(i));
        },
        onIndent: () => _structural(_model.indent(i, _caret(i))),
        onOutdent: () => _structural(_model.outdent(i, _caret(i))),
        onToggleCheckbox: () => _structural(_model.toggleCheckbox(i, _caret(i))),
        onUp: () => i == 0 ? _titleFocus.requestFocus() : _focusRow(i - 1, end: true),
        onDown: () => _focusRow(i + 1, end: false),
      );

  void _focusRow(int i, {required bool end}) {
    if (i < 0 || i >= _rows.length) return;
    final r = _rows[i];
    r.focus.requestFocus();
    r.text.selection = TextSelection.collapsed(offset: end ? r.text.text.length : 0);
  }

  Future<void> _moveTo() async {
    final path = _path;
    if (path == null) return;
    final dest = await pickFolder(context, folders: c.allFolders, current: parentOf(path));
    if (dest == null) return;
    await _save(push: false);
    final to = await c.moveNote(path, dest);
    setState(() => _path = to);
  }

  Future<void> _renameFile() async {
    final path = _path;
    if (path == null) return;
    await _save(push: false);
    final to = await c.moveNote(path, parentOf(path));
    setState(() => _path = to);
  }

  Future<void> _delete() async {
    final path = _path;
    final ok = await confirm(
      context,
      title: 'Delete this note?',
      body: 'It disappears from every device at the next sync. Its history stays in the GitHub repo.',
      action: 'Delete note',
    );
    if (!ok || !mounted) return;
    _closed = true;
    _debounce?.cancel();
    if (path != null) await c.deleteNote(path);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _close();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _flush,
        },
        child: Scaffold(
          backgroundColor: narrow ? p.card : p.desk,
          appBar: _bar(p, narrow),
          body: _loading
              ? const SizedBox.shrink()
              : Column(children: [
                  Expanded(child: _card(p, narrow)),
                  if (narrow) _toolbar(p),
                ]),
        ),
      ),
    );
  }

  PreferredSizeWidget _bar(Palette p, bool narrow) {
    final folder = _path != null ? parentOf(_path!) : widget.folder;
    return AppBar(
      backgroundColor: narrow ? p.card : p.desk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: p.ink,
      titleSpacing: 0,
      leading: IconButton(
        tooltip: 'Close and save',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        folder.isEmpty || folder == recentFolder ? 'Notes' : folder.replaceAll('/', ' / '),
        style: TextStyle(fontSize: 14, color: p.muted),
      ),
      actions: [
        ListenableBuilder(
          listenable: c,
          builder: (_, _) => SyncBadge(
            status: c.status,
            compact: narrow,
            onSync: _flush,
            onSettings: widget.onSettings,
          ),
        ),
        if (!narrow) ...[
          const SizedBox(width: 8),
          ..._itemButtons(p),
        ],
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) => switch (v) {
            'move' => _moveTo(),
            'rename' => _renameFile(),
            'delete' => _delete(),
            _ => null,
          },
          itemBuilder: (_) => [
            if (_path != null) const PopupMenuItem(value: 'move', child: Text('Move to folder…')),
            if (_path != null) const PopupMenuItem(value: 'rename', child: Text('Rename file after title')),
            const PopupMenuItem(value: 'delete', child: Text('Delete note')),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  List<Widget> _itemButtons(Palette p) => [
        IconButton(
          tooltip: 'Checkbox (Ctrl+Enter)',
          icon: const Icon(Icons.check_box_outlined),
          onPressed: () => _structural(_model.toggleCheckbox(_current, _caret(_current))),
        ),
        IconButton(
          tooltip: 'Outdent (Shift+Tab)',
          icon: const Icon(Icons.format_indent_decrease),
          onPressed: () => _structural(_model.outdent(_current, _caret(_current))),
        ),
        IconButton(
          tooltip: 'Indent (Tab)',
          icon: const Icon(Icons.format_indent_increase),
          onPressed: () => _structural(_model.indent(_current, _caret(_current))),
        ),
      ];

  Widget _toolbar(Palette p) => Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.border))),
        child: SafeArea(
          top: false,
          child: Row(children: [
            ..._itemButtons(p),
            const Spacer(),
            IconButton(
              tooltip: 'New item',
              icon: const Icon(Icons.keyboard_return),
              onPressed: () => _structural(_model.enter(_current, _caret(_current))),
            ),
          ]),
        ),
      );

  Widget _card(Palette p, bool narrow) {
    final hpad = narrow ? 16.0 : 36.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(narrow ? 0 : 24, narrow ? 0 : 8, narrow ? 0 : 24, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(narrow ? 0 : 3),
                border: narrow ? null : Border.all(color: p.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(hpad, narrow ? 18 : 30, hpad, 14),
                  child: TextField(
                    controller: _title,
                    focusNode: _titleFocus,
                    style: titleText(p, size: narrow ? 24 : 28),
                    maxLines: null,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => _changed(),
                    onEditingComplete: () => _focusRow(0, end: false),
                    decoration: bareField(
                      hint: 'Title',
                      hintStyle: titleText(p, size: narrow ? 24 : 28).copyWith(color: p.muted.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
                Container(height: 2, color: p.accent),
                CustomPaint(
                  painter: RuledPaper(p.rule, top: 10),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hpad - 8, 10, hpad, 24 + ruleHeight * 3),
                    child: Column(children: [
                      for (var i = 0; i < _rows.length; i++)
                        ItemRow(
                          key: ObjectKey(_rows[i]),
                          line: _model.lines[i],
                          controller: _rows[i].text,
                          focusNode: _rows[i].focus,
                          keys: _keys(i),
                          onChanged: (t) {
                            final f = _model.setText(i, t);
                            if (f != null) {
                              _structural(f);
                            } else {
                              _changed();
                            }
                          },
                          onChecked: (v) {
                            setState(() => _model.setChecked(i, v));
                            _changed();
                          },
                        ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _focusRow(_rows.length - 1, end: true),
                        child: const SizedBox(height: ruleHeight * 2, width: double.infinity),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
