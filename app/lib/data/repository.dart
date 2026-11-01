import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Where the app's showtimes come from: Supabase live (supabase_repository.dart),
/// with the scraper's output bundled as assets (copied from scraper/out) as the
/// offline fallback. The rest of the app only sees [CatalogData].
abstract interface class ShowtimesRepository {
  Future<CatalogData> load();
}

class CatalogData {
  CatalogData({
    required this.cinemas,
    required this.movies,
    required this.showtimes,
  });

  final Map<String, Cinema> cinemas;
  final Map<String, Movie> movies;

  /// Sorted by start time.
  final List<Showtime> showtimes;
}

class AssetShowtimesRepository implements ShowtimesRepository {
  static const _sources = ['renaissance', 'scene', 'premiere', 'elcinema'];

  @override
  Future<CatalogData> load() async {
    final raw = <String, String>{
      'catalog': await rootBundle.loadString('assets/data/catalog.json'),
      for (final s in _sources)
        s: await rootBundle.loadString('assets/data/$s.json'),
    };
    // A few MB of JSON: parse off the UI thread so the splash keeps animating.
    return compute(_parse, raw);
  }
}

CatalogData _parse(Map<String, String> raw) {
  final catalog = jsonDecode(raw['catalog']!) as Map<String, dynamic>;
  final filmToMovie = (catalog['filmToMovie'] as Map).cast<String, String>();
  final movies = {
    for (final m in (catalog['movies'] as List).cast<Map<String, dynamic>>())
      m['id'] as String: Movie.fromJson(m),
  };

  final cinemas = <String, Cinema>{};
  final showtimes = <Showtime>[];
  for (final entry in raw.entries) {
    if (entry.key == 'catalog') continue;
    final result = jsonDecode(entry.value) as Map<String, dynamic>;
    for (final c in (result['cinemas'] as List).cast<Map<String, dynamic>>()) {
      cinemas[c['id'] as String] = Cinema.fromJson(c);
    }
    for (final s
        in (result['showtimes'] as List).cast<Map<String, dynamic>>()) {
      final movieId = filmToMovie[s['filmId']];
      if (movieId != null && movies.containsKey(movieId))
        showtimes.add(Showtime.fromJson(s, movieId));
    }
  }
  showtimes.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return CatalogData(cinemas: cinemas, movies: movies, showtimes: showtimes);
}
