import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The last catalog Supabase sent, kept on the phone so the app opens on it
/// at once and refreshes behind it. Phones only: on the web there's no file
/// to keep it in, and the app loads live as before.
class CatalogCache {
  CatalogCache._(this._file);

  /// Older than this and it's no use opening on.
  static const maxAge = Duration(days: 2);

  static Future<CatalogCache?>? _opening;

  static Future<CatalogCache?> open() => _opening ??= _open();

  static Future<CatalogCache?> _open() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return CatalogCache._(File('${dir.path}/catalog-cache.json'));
    } catch (e) {
      debugPrint('No catalog cache: $e');
      return null;
    }
  }

  @visibleForTesting
  factory CatalogCache.at(File file) => CatalogCache._(file);

  final File _file;

  /// Supabase's response bodies, as SupabaseShowtimesRepository parses them,
  /// or null when there's nothing recent enough.
  Future<List<String>?> read({DateTime? now}) async {
    try {
      if (!await _file.exists()) return null;
      final saved =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      final at = DateTime.parse(saved['savedAt'] as String);
      if ((now ?? DateTime.now()).difference(at) > maxAge) return null;
      return (saved['bodies'] as List).cast<String>();
    } catch (e) {
      debugPrint('Catalog cache unreadable: $e');
      return null;
    }
  }

  Future<void> write(List<String> bodies, {DateTime? now}) async {
    try {
      // Written aside then moved, so a crash never leaves half a file.
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'savedAt': (now ?? DateTime.now()).toIso8601String(),
          'bodies': bodies,
        }),
        flush: true,
      );
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Saving the catalog cache failed: $e');
    }
  }
}
