import 'library.dart';

const _map = {
  'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', 'æ': 'ae',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o', 'œ': 'oe',
  'ù': 'u', 'ú': 'u', 'û': 'u',
  'ý': 'y', 'ÿ': 'y',
};

/// Lowercases and strips common diacritics, so "Jörg" matches "jorg".
String normalizeForSearch(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_map[ch] ?? ch);
  }
  return b.toString();
}

/// Every whitespace-separated term must appear in "artist fileName".
List<AudioFileRef> searchLibrary(Library lib, String query) {
  final terms = normalizeForSearch(query).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (terms.isEmpty) return lib.allFiles;
  return [
    for (final f in lib.allFiles)
      if (terms.every(normalizeForSearch('${f.artist} ${f.fileName}').contains)) f,
  ];
}
