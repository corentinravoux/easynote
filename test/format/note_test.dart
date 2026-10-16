import 'package:easynote/format/note.dart';
import 'package:flutter_test/flutter_test.dart';

const specExample = '# Lyα tomography\n'
    '- void finder on DESI DR2 maps\n'
    '  - sub-idea, indented two spaces\n'
    '- [ ] check Wiener filter σ_g dependence\n'
    '- [x] compare with VIDE\n';

void main() {
  group('round trip is byte-identical', () {
    final cases = <String, String>{
      'spec example': specExample,
      'no title line': '- a\n- b\n',
      'no trailing newline': '# T\n- a',
      'empty file': '',
      'title only': '# T\n',
      'blank lines': '# T\n\n- a\n\n\n',
      'star bullet': '# T\n* star\n',
      'capital X': '# T\n- [X] cap\n',
      'tab indent': '# T\n\t- tab\n',
      'three spaces': '# T\n   - three\n',
      'CRLF': '# T\r\n- a\r\n',
      'box without trailing space': '# T\n- [ ]\n',
      'empty bullet with space': '# T\n- \n',
      'hash without space': '#NoSpace\n- a\n',
      'second heading': '# T\n## sub\n- a\n',
      'unicode': '# Écart σ₈\n- [ ] ∇·v ≈ −aHfδ\n',
      'deep indent': '# T\n- a\n  - b\n    - [x] c\n',
    };
    cases.forEach((name, src) {
      test(name, () => expect(serializeNote(parseNote(src)), src));
    });
  });

  test('parses the spec example', () {
    final n = parseNote(specExample);
    expect(n.title, 'Lyα tomography');
    expect(n.hasTitleLine, isTrue);
    expect(n.lines.map((l) => l.kind).toList(),
        [ItemKind.bullet, ItemKind.bullet, ItemKind.todo, ItemKind.done]);
    expect(n.lines.map((l) => l.indent).toList(), [0, 1, 0, 0]);
    expect(n.lines[2].text, 'check Wiener filter σ_g dependence');
  });

  test('non-canonical lines stay plain with raw text', () {
    final n = parseNote('# T\n* star\n   - three\n- [X] cap\n');
    expect(n.lines.every((l) => l.kind == ItemKind.plain), isTrue);
    expect(n.lines[1].text, '   - three');
  });

  test('box-like lines without canonical form stay plain', () {
    final n = parseNote('# T\n- [ ]\n- [X] a\n');
    expect(n.lines.map((l) => l.kind).toList(), [ItemKind.plain, ItemKind.plain]);
  });

  test('a file without title line has an empty title', () {
    final n = parseNote('- a\n');
    expect(n.title, '');
    expect(n.hasTitleLine, isFalse);
  });

  test('serializes a new note canonically', () {
    final n = Note(title: 'T', lines: [
      const NoteLine(ItemKind.todo, 'a'),
      const NoteLine(ItemKind.bullet, 'b', indent: 1),
      const NoteLine(ItemKind.done, 'c'),
    ]);
    expect(serializeNote(n), '# T\n- [ ] a\n  - b\n- [x] c\n');
  });

  test('a note with no lines serializes as its title', () {
    expect(serializeNote(Note(title: 'T')), '# T\n');
  });

  group('previewOf', () {
    test('renders boxes, indents, skips title, caps lines', () {
      final n = parseNote(specExample);
      expect(previewOf(n), [
        '• void finder on DESI DR2 maps',
        '  • sub-idea, indented two spaces',
        '☐ check Wiener filter σ_g dependence',
        '☑ compare with VIDE',
      ]);
      expect(previewOf(n, maxLines: 2).length, 2);
    });
    test('drops blank lines', () {
      expect(previewOf(parseNote('# T\n\n- a\n\n')), ['• a']);
    });
  });

  test('counts checkboxes', () {
    final n = parseNote(specExample);
    expect(n.todoCount, 2);
    expect(n.doneCount, 1);
  });
}
