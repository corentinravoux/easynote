import '../store/paths.dart';

const _translit = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae',
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i',
  'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
  'ö': 'o', 'ø': 'o', 'œ': 'oe', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
  'α': 'a', 'β': 'b', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'e',
  'θ': 'th', 'ι': 'i', 'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'x',
  'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'ς': 's', 'τ': 't', 'υ': 'u',
  'φ': 'ph', 'χ': 'ch', 'ψ': 'ps', 'ω': 'o',
};

/// Lowercase [s] and replace accented Latin and Greek letters by ASCII.
/// Used for slugs and for accent-insensitive search.
String fold(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_translit[ch] ?? ch);
  }
  return b.toString();
}

const _maxSlug = 60;

/// File-name stem for a note titled [title]: `Lyα tomography` → `lya-tomography`.
String slugify(String title) {
  var s = fold(title).replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > _maxSlug) {
    s = s.substring(0, _maxSlug).replaceAll(RegExp(r'-+$'), '');
  }
  return s.isEmpty ? 'note' : s;
}

/// A path in [folder] for a new note titled [title] that collides with none
/// of [existing] (compared case-insensitively, as on Android storage).
String uniquePath(String folder, String title, Set<String> existing) {
  final taken = {for (final p in existing) p.toLowerCase()};
  final stem = slugify(title);
  var candidate = joinPath(folder, '$stem.md');
  for (var n = 2; taken.contains(candidate.toLowerCase()); n++) {
    candidate = joinPath(folder, '$stem-$n.md');
  }
  return candidate;
}
