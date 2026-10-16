import 'package:easynote/format/note.dart';
import 'package:easynote/ui/editor/editor_model.dart';
import 'package:flutter_test/flutter_test.dart';

NoteLine bl(String t, [int i = 0]) => NoteLine(ItemKind.bullet, t, indent: i);
NoteLine todo(String t, [int i = 0]) => NoteLine(ItemKind.todo, t, indent: i);
NoteLine done(String t, [int i = 0]) => NoteLine(ItemKind.done, t, indent: i);

void main() {
  test('an empty note starts with one empty bullet', () {
    expect(EditorModel([]).lines, [bl('')]);
  });

  group('enter', () {
    test('splits at the caret, keeping kind and indent', () {
      final m = EditorModel([bl('hello world', 1)]);
      expect(m.enter(0, 5), (index: 1, caret: 0));
      expect(m.lines, [bl('hello', 1), bl(' world', 1)]);
    });
    test('a done item continues as an open checkbox', () {
      final m = EditorModel([done('a')]);
      m.enter(0, 1);
      expect(m.lines[1], todo(''));
    });
    test('on an empty indented item outdents it', () {
      final m = EditorModel([bl('a'), todo('', 1)]);
      expect(m.enter(1, 0), (index: 1, caret: 0));
      expect(m.lines[1], todo(''));
    });
    test('on an empty top-level item does nothing', () {
      final m = EditorModel([bl('a'), bl('')]);
      expect(m.enter(1, 0), isNull);
      expect(m.lines.length, 2);
    });
    test('after a plain line starts a bullet', () {
      final m = EditorModel([const NoteLine(ItemKind.plain, 'text')]);
      m.enter(0, 4);
      expect(m.lines[1], bl(''));
    });
  });

  group('backspace at start', () {
    test('deletes an empty item and focuses the end of the previous', () {
      final m = EditorModel([bl('abc'), bl('')]);
      expect(m.backspaceAtStart(1), (index: 0, caret: 3));
      expect(m.lines, [bl('abc')]);
    });
    test('merges a non-empty item into the previous', () {
      final m = EditorModel([bl('ab'), todo('cd')]);
      expect(m.backspaceAtStart(1), (index: 0, caret: 2));
      expect(m.lines, [bl('abcd')]);
    });
    test('does nothing on the first item', () {
      expect(EditorModel([bl('')]).backspaceAtStart(0), isNull);
    });
  });

  group('indent', () {
    test('is limited to one level below the item above', () {
      final m = EditorModel([bl('a'), bl('b')]);
      expect(m.indent(1, 0), isNotNull);
      expect(m.indent(1, 0), isNull);
      expect(m.lines[1].indent, 1);
    });
    test('the first item cannot be indented', () {
      expect(EditorModel([bl('a')]).indent(0, 0), isNull);
    });
    test('outdent stops at zero', () {
      final m = EditorModel([bl('a'), bl('b', 1)]);
      m.outdent(1, 0);
      expect(m.outdent(1, 0), isNull);
      expect(m.lines[1].indent, 0);
    });
  });

  test('toggle checkbox both ways, and tick', () {
    final m = EditorModel([bl('a')]);
    m.toggleCheckbox(0, 0);
    expect(m.lines[0], todo('a'));
    m.setChecked(0, true);
    expect(m.lines[0], done('a'));
    m.toggleCheckbox(0, 0);
    expect(m.lines[0], bl('a'));
  });

  test('pasting several lines makes several items', () {
    final m = EditorModel([todo('', 1)]);
    expect(m.setText(0, 'x\ny\nz'), (index: 2, caret: 1));
    expect(m.lines, [todo('x', 1), todo('y', 1), todo('z', 1)]);
  });

  test('saved drops trailing empty items', () {
    final m = EditorModel([bl('a'), bl(''), todo('')]);
    expect(m.saved, [bl('a')]);
  });
}
