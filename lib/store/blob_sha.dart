import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The SHA-1 git assigns to a blob holding [bytes].
///
/// Comparing this against the SHA recorded at the last sync tells whether a
/// local file changed, without keeping a dirty flag that a crash could lose.
String gitBlobSha(List<int> bytes) {
  final header = ascii.encode('blob ${bytes.length}\u0000');
  return sha1.convert([...header, ...bytes]).toString();
}
