/// The easynote file format: a `# title` line, then items.
///
/// Only the canonical forms are parsed (`- `, `- [ ] `, `- [x] `, indented by
/// two spaces per level). Any other line is kept verbatim as [ItemKind.plain],
/// so a note edited by hand or on github.com is never rewritten unless the
/// user edits it here.
library;

enum ItemKind { bullet, todo, done, plain }

class NoteLine {
  final ItemKind kind;

  /// Nesting level. Always 0 for plain lines, whose leading spaces stay in
  /// [text].
  final int indent;

  /// Item text without its marker; for a plain line, the raw line.
  final String text;

  const NoteLine(this.kind, this.text, {this.indent = 0});

  bool get isCheckbox => kind == ItemKind.todo || kind == ItemKind.done;

  NoteLine copyWith({ItemKind? kind, String? text, int? indent}) =>
      NoteLine(kind ?? this.kind, text ?? this.text,
          indent: indent ?? this.indent);

  @override
  bool operator ==(Object other) =>
      other is NoteLine &&
      other.kind == kind &&
      other.indent == indent &&
      other.text == text;

  @override
  int get hashCode => Object.hash(kind, indent, text);

  @override
  String toString() => 'NoteLine($kind, $indent, "$text")';
}

class Note {
  String title;

  /// False when the file did not start with `# `; the title is then not
  /// written back, so such a file round-trips unchanged.
  bool hasTitleLine;
  List<NoteLine> lines;
  bool trailingNewline;

  Note({
    required this.title,
    List<NoteLine>? lines,
    this.hasTitleLine = true,
    this.trailingNewline = true,
  }) : lines = lines ?? [];

  int get todoCount => lines.where((l) => l.isCheckbox).length;
  int get doneCount => lines.where((l) => l.kind == ItemKind.done).length;
}

final _title = RegExp(r'^# (.*)$');
final _box = RegExp(r'^((?:  )*)- \[( |x)\] (.*)$');
// A bullet whose text looks like a non-canonical checkbox (`- [X] a`, `- [ ]`)
// stays plain, so it is not shown as a bullet holding "[X] a".
final _bullet = RegExp(r'^((?:  )*)- (?!\[[ xX]\])(.*)$');

Note parseNote(String src) {
  if (src.isEmpty) {
    return Note(title: '', hasTitleLine: false, trailingNewline: false);
  }
  final trailingNewline = src.endsWith('\n');
  final raw = (trailingNewline ? src.substring(0, src.length - 1) : src)
      .split('\n');

  var title = '';
  var hasTitleLine = false;
  var start = 0;
  final m = _title.firstMatch(raw.first);
  if (m != null) {
    title = m.group(1)!;
    hasTitleLine = true;
    start = 1;
  }
  final lines = [for (final l in raw.skip(start)) _parseLine(l)];
  return Note(
    title: title,
    lines: lines,
    hasTitleLine: hasTitleLine,
    trailingNewline: trailingNewline,
  );
}

NoteLine _parseLine(String line) {
  final box = _box.firstMatch(line);
  if (box != null) {
    return NoteLine(
      box.group(2) == 'x' ? ItemKind.done : ItemKind.todo,
      box.group(3)!,
      indent: box.group(1)!.length ~/ 2,
    );
  }
  final bullet = _bullet.firstMatch(line);
  if (bullet != null) {
    return NoteLine(ItemKind.bullet, bullet.group(2)!,
        indent: bullet.group(1)!.length ~/ 2);
  }
  return NoteLine(ItemKind.plain, line);
}

String serializeLine(NoteLine l) {
  final pad = '  ' * l.indent;
  return switch (l.kind) {
    ItemKind.bullet => '$pad- ${l.text}',
    ItemKind.todo => '$pad- [ ] ${l.text}',
    ItemKind.done => '$pad- [x] ${l.text}',
    ItemKind.plain => l.text,
  };
}

String serializeNote(Note note) {
  final out = <String>[
    if (note.hasTitleLine) '# ${note.title}',
    for (final l in note.lines) serializeLine(l),
  ];
  if (out.isEmpty) return '';
  final body = out.join('\n');
  return note.trailingNewline ? '$body\n' : body;
}

/// Display lines for a card or the widget: items with their markers drawn as
/// symbols, blank lines dropped, the title excluded.
List<String> previewOf(Note note, {int maxLines = 6}) {
  final out = <String>[];
  for (final l in note.lines) {
    if (out.length >= maxLines) break;
    if (l.text.trim().isEmpty) continue;
    final pad = '  ' * l.indent;
    out.add(switch (l.kind) {
      ItemKind.bullet => '$pad• ${l.text}',
      ItemKind.todo => '$pad☐ ${l.text}',
      ItemKind.done => '$pad☑ ${l.text}',
      ItemKind.plain => l.text.trim(),
    });
  }
  return out;
}
