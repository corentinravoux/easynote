import '../../format/note.dart';

/// Where to put the caret after an edit.
typedef Focus2 = ({int index, int caret});

/// Pure editing operations on a note's item list. Each returns the row and
/// caret offset to focus, or null when nothing changed.
class EditorModel {
  final List<NoteLine> lines;

  EditorModel(List<NoteLine> lines)
      : lines = lines.isEmpty ? [const NoteLine(ItemKind.bullet, '')] : List.of(lines);

  static ItemKind _continued(ItemKind k) => switch (k) {
        ItemKind.done => ItemKind.todo,
        ItemKind.plain => ItemKind.bullet,
        _ => k,
      };

  /// Enter with the caret at [caret]: split the item. On an empty item,
  /// outdent it if indented, otherwise do nothing.
  Focus2? enter(int i, int caret) {
    final l = lines[i];
    if (l.text.isEmpty && l.kind != ItemKind.plain) {
      if (l.indent == 0) return null;
      lines[i] = l.copyWith(indent: l.indent - 1);
      return (index: i, caret: 0);
    }
    final c = caret.clamp(0, l.text.length);
    lines[i] = l.copyWith(text: l.text.substring(0, c));
    lines.insert(
        i + 1,
        NoteLine(_continued(l.kind), l.text.substring(c),
            indent: l.kind == ItemKind.plain ? 0 : l.indent));
    return (index: i + 1, caret: 0);
  }

  /// Backspace with the caret at the start of item [i]: delete an empty
  /// item, or merge a non-empty one into the item above.
  Focus2? backspaceAtStart(int i) {
    if (i == 0) return null;
    final l = lines[i], prev = lines[i - 1];
    lines.removeAt(i);
    if (l.text.isNotEmpty) {
      lines[i - 1] = prev.copyWith(text: prev.text + l.text);
    }
    return (index: i - 1, caret: prev.text.length);
  }

  Focus2? indent(int i, int caret) {
    final l = lines[i];
    if (l.kind == ItemKind.plain) return null;
    final max = i == 0 ? 0 : lines[i - 1].indent + 1;
    if (l.indent >= max) return null;
    lines[i] = l.copyWith(indent: l.indent + 1);
    return (index: i, caret: caret);
  }

  Focus2? outdent(int i, int caret) {
    final l = lines[i];
    if (l.indent == 0) return null;
    lines[i] = l.copyWith(indent: l.indent - 1);
    return (index: i, caret: caret);
  }

  /// Bullet or plain line becomes an open checkbox; a checkbox becomes a
  /// bullet.
  Focus2 toggleCheckbox(int i, int caret) {
    final l = lines[i];
    lines[i] = l.isCheckbox
        ? l.copyWith(kind: ItemKind.bullet)
        : l.copyWith(kind: ItemKind.todo);
    return (index: i, caret: caret);
  }

  void setChecked(int i, bool done) {
    final l = lines[i];
    if (!l.isCheckbox) return;
    lines[i] = l.copyWith(kind: done ? ItemKind.done : ItemKind.todo);
  }

  /// Replace the text of item [i]. Text holding newlines (a paste) becomes
  /// several items of the same kind.
  Focus2? setText(int i, String text) {
    final l = lines[i];
    if (!text.contains('\n')) {
      lines[i] = l.copyWith(text: text);
      return null;
    }
    final parts = text.split('\n');
    lines[i] = l.copyWith(text: parts.first);
    for (var k = 1; k < parts.length; k++) {
      lines.insert(i + k,
          NoteLine(_continued(l.kind), parts[k], indent: l.kind == ItemKind.plain ? 0 : l.indent));
    }
    return (index: i + parts.length - 1, caret: parts.last.length);
  }

  /// Items without the trailing empty bullets a user leaves while typing.
  List<NoteLine> get saved {
    final out = List.of(lines);
    while (out.isNotEmpty && out.last.text.isEmpty && out.last.kind != ItemKind.plain) {
      out.removeLast();
    }
    return out;
  }
}
