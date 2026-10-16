import 'package:easynote/format/slug.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slugify', () {
    test('greek letters transliterate', () {
      expect(slugify('Lyα tomography'), 'lya-tomography');
    });
    test('accents, symbols and spacing', () {
      expect(slugify('  Écart σ_8 / S8 !'), 'ecart-s-8-s8');
    });
    test('nothing usable gives note', () {
      expect(slugify('???'), 'note');
      expect(slugify(''), 'note');
    });
    test('long titles are cut without trailing dash', () {
      final s = slugify('${'a' * 59} b ${'c' * 40}');
      expect(s.length, lessThanOrEqualTo(60));
      expect(s.endsWith('-'), isFalse);
    });
    test('capital greek and ligatures', () {
      expect(slugify('ΛCDM œuvre'), 'lcdm-oeuvre');
    });
  });

  group('fold', () {
    test('lowercases and strips accents but keeps spaces', () {
      expect(fold('Écart Lyα'), 'ecart lya');
    });
  });

  group('uniquePath', () {
    test('root folder has no leading slash', () {
      expect(uniquePath('', 'Inbox', {}), 'inbox.md');
    });
    test('nested folder', () {
      expect(uniquePath('lya/tomo', 'Maps', {}), 'lya/tomo/maps.md');
    });
    test('collisions count up', () {
      expect(uniquePath('lya', 'P1D', {'lya/p1d.md'}), 'lya/p1d-2.md');
      expect(uniquePath('lya', 'P1D', {'lya/p1d.md', 'lya/p1d-2.md'}),
          'lya/p1d-3.md');
    });
    test('collision check ignores case', () {
      expect(uniquePath('', 'A', {'A.md'}), 'a-2.md');
    });
  });
}
