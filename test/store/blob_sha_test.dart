import 'dart:convert';

import 'package:easynote/store/blob_sha.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Expected values come from `git hash-object --stdin`.
  test('empty blob', () {
    expect(gitBlobSha(utf8.encode('')), 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391');
  });
  test('ascii blob', () {
    expect(gitBlobSha(utf8.encode('hello\n')), 'ce013625030ba8dba906f756967f9e9ca394464a');
  });
  test('multibyte blob counts bytes, not characters', () {
    expect(gitBlobSha(utf8.encode('# Lyα\n')), 'f6db412a97c48fdb5a2cc9fbfd940eb1a827c1fa');
  });
}
