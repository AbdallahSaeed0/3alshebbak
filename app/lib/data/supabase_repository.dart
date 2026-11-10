import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_data.dart';
import 'catalog_cache.dart';
import 'models.dart';
import 'repository.dart';

/// Reads the live catalog the scraper writes to Supabase (schema `shebbak`)
/// over its REST API, with the publishable key — read-only, safe to ship.
class SupabaseShowtimesRepository implements ShowtimesRepository {
  SupabaseShowtimesRepository({http.Client? client})
    : _client = client ?? http.Client();

  static const url = 'https://enmcbbwunzhjxgwehzuf.supabase.co';
  static const _publishableKey =
      'sb_publishable_f7K-cdE2gojpx4tXP8mNyQ_UKgrYgg1';

  /// The API returns at most this many rows per request; showtimes are paged.
  static const _page = 1000;
  static const _timeout = Duration(seconds: 20);

  final http.Client _client;

  /// Also used by push.dart to register the phone.
  static const headers = {
    'apikey': _publishableKey,
    'Accept-Profile': 'shebbak',
  };

  Future<http.Response> _get(
    String path, {
    Map<String, String> extra = const {},
  }) async {
    final res = await _client
        .get(Uri.parse('$url/rest/v1/$path'), headers: {...headers, ...extra})
        .timeout(_timeout);
    if (res.statusCode >= 300)
      throw Exception('Supabase $path: HTTP ${res.statusCode} ${res.body}');
    return res;
  }

  /// The whole catalog as one file on Supabase Storage's CDN, rewritten after
  /// every pipeline run (scraper/src/snapshot.ts): one download, about a
  /// quarter of a megabyte compressed, instead of a dozen database pages.
  static const snapshotUrl =
      '$url/storage/v1/object/public/shebbak-public/catalog.json';

  /// Older than this and the snapshot isn't being updated: ask the database.
  static const _snapshotMaxAge = Duration(minutes: 90);

  @override
  Future<CatalogData> load() async {
    try {
      final snapshot = await _loadSnapshot();
      if (snapshot != null) return snapshot;
    } catch (e) {
      debugPrint('Catalog snapshot unavailable, reading the database: $e');
    }
    return _loadFromDatabase();
  }

  Future<CatalogData?> _loadSnapshot() async {
    final res = await _client.get(Uri.parse(snapshotUrl)).timeout(_timeout);
    if (res.statusCode != 200) return null;
    final body = utf8.decode(res.bodyBytes);
    // {"v":1,"generatedAt":"…", …}: read the time without decoding it all.
    final at = RegExp(
      r'"generatedAt":"([^"]+)"',
    ).firstMatch(body.substring(0, body.length.clamp(0, 200)))?.group(1);
    final made = at == null ? null : DateTime.tryParse(at);
    if (made == null || DateTime.now().difference(made) > _snapshotMaxAge) {
      return null;
    }
    final data = await parse([body]);
    if (data.showtimes.isEmpty) return null;
    unawaited((await CatalogCache.open())?.write([body]));
    return data;
  }

  Future<CatalogData> _loadFromDatabase() async {
    // Shows that ended an hour ago are of no use; the rest of the schedule is.
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    const fields =
        'cinema_id,movie_id,business_date,starts_at,format,booking_url,price_egp';
    final showtimesPath =
        'showtimes?select=$fields&starts_at=gte.$since&order=starts_at,id';

    final results = await Future.wait([
      _get(
        'cinemas?select=id,chain,name,name_ar,city,area,url,attribution,'
        'lat,lng,location_approximate',
      ),
      _get(
        // Every column: newer ones (rating, trailer_key) may not exist yet
        // on an older database, and naming them would fail the request.
        'movies?select=*',
      ),
      // The first page also says how many rows there are in all.
      _get(
        showtimesPath,
        extra: {'Range': '0-${_page - 1}', 'Prefer': 'count=exact'},
      ),
    ]);

    final first = results[2];
    final total =
        int.tryParse(first.headers['content-range']?.split('/').last ?? '') ??
        0;
    final rest = await Future.wait([
      for (var from = _page; from < total; from += _page)
        _get(showtimesPath, extra: {'Range': '$from-${from + _page - 1}'}),
    ]);

    final bodies = [
      // Decoded as UTF-8 explicitly: without a charset header `body` would be
      // read as Latin-1 and garble every Arabic title.
      for (final r in [results[0], results[1], first, ...rest])
        utf8.decode(r.bodyBytes),
    ];
    final data = await parse(bodies);
    if (data.showtimes.isNotEmpty) {
      // Next launch opens on this at once (catalog_cache.dart).
      unawaited((await CatalogCache.open())?.write(bodies));
    }
    return data;
  }

  /// The catalog in [bodies] (cinemas, movies, then pages of showtimes), off
  /// the UI thread.
  static Future<CatalogData> parse(List<String> bodies) =>
      compute(_parse, bodies);

  /// The catalog saved on the last launch, when it's recent enough.
  static Future<CatalogData?> cached() async {
    final bodies = await (await CatalogCache.open())?.read();
    if (bodies == null) return null;
    try {
      final data = await parse(bodies);
      return data.showtimes.isEmpty ? null : data;
    } catch (e) {
      debugPrint('Cached catalog unusable: $e');
      return null;
    }
  }
}

/// [bodies] is either the database's answers (cinemas, movies, then pages of
/// showtimes) or one snapshot file holding all three.
CatalogData _parse(List<String> bodies) {
  List<Map<String, dynamic>> list(Object? rows) =>
      (rows as List).cast<Map<String, dynamic>>();
  final List<List<Map<String, dynamic>>> parts;
  if (bodies.length == 1) {
    final snapshot = jsonDecode(bodies.single) as Map<String, dynamic>;
    parts = [
      list(snapshot['cinemas']),
      list(snapshot['movies']),
      list(snapshot['showtimes']),
    ];
  } else {
    parts = [for (final b in bodies) list(jsonDecode(b))];
  }

  final cinemas = {
    for (final c in parts[0])
      c['id'] as String: Cinema(
        id: c['id'] as String,
        chain: c['chain'] as String,
        name: c['name'] as String,
        nameAr: c['name_ar'] as String?,
        city: c['city'] as String?,
        area: c['area'] as String?,
        url: c['url'] as String?,
        attribution: c['attribution'] as String?,
        lat: (c['lat'] as num?)?.toDouble(),
        lng: (c['lng'] as num?)?.toDouble(),
        locationApproximate: c['location_approximate'] as bool? ?? false,
      ),
  };
  final movies = {
    for (final m in parts[1])
      m['id'] as String: Movie(
        id: m['id'] as String,
        tmdbId: m['tmdb_id'] as int?,
        title: m['title'] as String,
        titleAr: m['title_ar'] as String?,
        originalTitle: m['original_title'] as String?,
        overview: m['overview'] as String?,
        posterPath: m['poster_path'] as String?,
        backdropPath: m['backdrop_path'] as String?,
        releaseDate: m['release_date'] as String?,
        runtime: m['runtime'] as int?,
        genres: (m['genres'] as List?)?.cast<String>() ?? const [],
        rating: (m['rating'] as num?)?.toDouble(),
        trailerKey: m['trailer_key'] as String?,
        fallbackPosterUrl: m['fallback_poster_url'] as String?,
      ),
  };

  final showtimes = <Showtime>[];
  for (final page in parts.skip(2)) {
    for (final s in page) {
      final cinemaId = s['cinema_id'] as String;
      final movieId = s['movie_id'] as String;
      if (!cinemas.containsKey(cinemaId) || !movies.containsKey(movieId))
        continue;
      final startsAt = DateTime.parse(s['starts_at'] as String);
      showtimes.add(
        Showtime(
          cinemaId: cinemaId,
          movieId: movieId,
          businessDate: s['business_date'] as String,
          startsAt: startsAt,
          // Stored as UTC; shown in Cairo time whatever the phone's time zone.
          wallClock: cairoWallClock(startsAt),
          format: s['format'] as String,
          bookingUrl: s['booking_url'] as String?,
          priceEgp: s['price_egp'] as int?,
        ),
      );
    }
  }
  showtimes.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return CatalogData(cinemas: cinemas, movies: movies, showtimes: showtimes);
}

/// Live data when there's a connection; the bundled snapshot when there isn't,
/// so the app always opens.
class FallbackShowtimesRepository implements ShowtimesRepository {
  FallbackShowtimesRepository(this.primary, this.fallback);

  final ShowtimesRepository primary;
  final ShowtimesRepository fallback;

  @override
  Future<CatalogData> load() async {
    try {
      final data = await primary.load();
      if (data.showtimes.isNotEmpty) {
        debugPrint(
          'Live catalog: ${data.cinemas.length} cinemas, ${data.movies.length} movies, '
          '${data.showtimes.length} showtimes',
        );
        return data;
      }
      debugPrint('Live catalog is empty; using the bundled snapshot');
    } catch (e) {
      debugPrint('Live catalog unavailable, using the bundled snapshot: $e');
    }
    return fallback.load();
  }
}
