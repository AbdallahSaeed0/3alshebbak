// Search that forgives how people type: Arabic or English, any letter case,
// with or without hamzas and diacritics, words in any order.

final _diacritics = RegExp('[ً-ٰٟـ]');
final _punctuation = RegExp(r"[^\p{L}\p{N}]+", unicode: true);

/// "أفاتار: الطريق" → "افاتار الطريق"; "Spider-Man" → "spider man".
String normalizeSearch(String s) {
  final out = StringBuffer();
  for (final ch in s.toLowerCase().replaceAll(_diacritics, '').runes) {
    out.write(switch (ch) {
      0x0623 || 0x0625 || 0x0622 || 0x0671 => 'ا', // أ إ آ ٱ
      0x0649 => 'ي', // ى
      0x0629 => 'ه', // ة
      0x0624 => 'و', // ؤ
      0x0626 => 'ي', // ئ
      >= 0x0660 && <= 0x0669 => String.fromCharCode(ch - 0x0660 + 0x30), // ٠-٩
      _ => String.fromCharCode(ch),
    });
  }
  return out.toString().replaceAll(_punctuation, ' ').trim();
}

/// A query prepared once and matched against many items.
class SearchQuery {
  SearchQuery(String raw)
    : _words = normalizeSearch(
        raw,
      ).split(' ').where((w) => w.isNotEmpty).toList();

  final List<String> _words;

  bool get isEmpty => _words.isEmpty;

  /// Every word of the query appears in one of [fields]. Spaces don't count,
  /// so "spiderman" finds "Spider-Man" and "سبايدر مان" finds "سبايدرمان".
  bool matches(Iterable<String?> fields) {
    if (_words.isEmpty) return true;
    final text = normalizeSearch(fields.whereType<String>().join(' '));
    final joined = text.replaceAll(' ', '');
    return _words.every((w) => text.contains(w) || joined.contains(w));
  }
}
