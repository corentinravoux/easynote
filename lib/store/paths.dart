/// Posix path helpers for note-tree paths. A path is relative to the notes
/// root, uses `/`, and the root itself is the empty string.
library;

const keepFile = '.keep';

/// Whether [path] belongs to the note tree that easynote syncs.
///
/// Tracked: every `*.md` file and every folder `.keep` marker. Ignored: any
/// path with a hidden segment (except a `.keep` basename), the root
/// `README.md`, and a `.keep` at the root.
bool isTracked(String path) {
  if (path.isEmpty) return false;
  final segments = path.split('/');
  final base = segments.last;
  for (final s in segments.sublist(0, segments.length - 1)) {
    if (s.isEmpty || s.startsWith('.')) return false;
  }
  if (base == keepFile) return segments.length > 1;
  if (base.startsWith('.')) return false;
  if (path == 'README.md') return false;
  return base.endsWith('.md');
}

bool isKeep(String path) => basenameOf(path) == keepFile;

String parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

String basenameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

String joinPath(String folder, String name) =>
    folder.isEmpty ? name : '$folder/$name';

/// Whether [path] lies inside [folder] (at any depth). The root contains all.
bool isUnder(String path, String folder) =>
    folder.isEmpty || path.startsWith('$folder/');
