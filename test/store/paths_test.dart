import 'package:easynote/store/paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isTracked', () {
    for (final p in [
      'a.md',
      'lya/tomo/maps.md',
      'lya/.keep',
      'x.conflict-laptop-20261016-1200.md',
      'sub/README.md',
    ]) {
      test('tracks $p', () => expect(isTracked(p), isTrue));
    }
    for (final p in [
      'README.md',
      '.github/x.md',
      'a/.hidden.md',
      'a/b.txt',
      '.keep',
      '.easynote/state.md',
      '',
    ]) {
      test('ignores "$p"', () => expect(isTracked(p), isFalse));
    }
  });

  test('parentOf and basenameOf', () {
    expect(parentOf('a.md'), '');
    expect(parentOf('lya/tomo/maps.md'), 'lya/tomo');
    expect(basenameOf('lya/tomo/maps.md'), 'maps.md');
    expect(basenameOf('a.md'), 'a.md');
  });

  test('joinPath skips the root', () {
    expect(joinPath('', 'a.md'), 'a.md');
    expect(joinPath('lya', 'a.md'), 'lya/a.md');
  });

  test('isKeep', () {
    expect(isKeep('lya/.keep'), isTrue);
    expect(isKeep('lya/a.md'), isFalse);
  });
}
