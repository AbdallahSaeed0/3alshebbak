import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_data.dart';
import 'repository.dart';
import 'models.dart';
import 'supabase_repository.dart';

/// What kind of news a notification brought about one film.
enum NewsKind {
  /// Tickets went on sale where there were none before.
  opened,

  /// Booking now reaches days that weren't on sale.
  days,

  /// More showtimes on days already on sale.
  shows,
}

/// One film in a notification, and the cinemas the news is at (null: the
/// notification didn't say, so the phone's own cinemas are used).
class NewsFilm {
  const NewsFilm({required this.movieId, required this.kind, this.cinemas});

  final String movieId;
  final NewsKind kind;
  final List<String>? cinemas;
}

/// A tapped showtimes notification: its films and the window their new
/// showtimes were first seen in. Built from the notification's data, which
/// the pipeline writes (scraper/src/notify.ts, alertData).
class AlertNews {
  const AlertNews({
    required this.films,
    required this.since,
    required this.until,
    this.title,
    this.body,
  });

  final List<NewsFilm> films;
  final DateTime since;
  final DateTime until;

  /// The notification's own text, shown at the top of its screen.
  final String? title;
  final String? body;

  /// Null when [data] isn't a showtimes notification (an update notice, or
  /// one sent before notifications carried their details).
  static AlertNews? fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    if (data['type'] != 'alert') return null;
    try {
      final films = [
        for (final f in jsonDecode(data['films'] as String) as List)
          NewsFilm(
            movieId: f['m'] as String,
            kind: NewsKind.values.firstWhere(
              (k) => k.name == f['k'],
              orElse: () => NewsKind.shows,
            ),
            cinemas: (f['c'] as List?)?.cast<String>(),
          ),
      ];
      if (films.isEmpty) return null;
      return AlertNews(
        films: films,
        since: DateTime.parse(data['since'] as String),
        until: DateTime.parse(data['until'] as String),
        title: title,
        body: body,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The showtimes a notification announced, as the catalog's news recorded
/// them (scraper/src/snapshot.ts, attachShows): the same shows the alert was
/// worked out from. Each is matched to the catalog's showtime for its format
/// and booking link. Null when the catalog has no shows for this news, and
/// the database has to be asked instead ([fetchNews]).
List<Showtime>? recordedShows(AlertNews news, CatalogData catalog) {
  final now = DateTime.now();
  final shows = <Showtime>[];
  var found = false;
  for (final f in news.films) {
    for (final n in catalog.news) {
      if (n.movieId != f.movieId ||
          n.at.difference(news.until).inSeconds.abs() > 5 ||
          n.shows.isEmpty) {
        continue;
      }
      found = true;
      n.shows.forEach((cinema, starts) {
        if (!catalog.cinemas.containsKey(cinema)) return;
        for (final start in starts) {
          if (!start.isAfter(now)) continue;
          shows.add(
            _listed(catalog, f.movieId, cinema, start) ??
                _bare(f.movieId, cinema, start),
          );
        }
      });
    }
  }
  if (!found) return null;
  shows.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return shows;
}

/// The catalog's own showtime for that film, cinema and start, if listed.
Showtime? _listed(
  CatalogData catalog,
  String movie,
  String cinema,
  DateTime start,
) {
  for (final s in catalog.showtimes) {
    if (s.movieId == movie &&
        s.cinemaId == cinema &&
        s.startsAt.isAtSameMomentAs(start)) {
      return s;
    }
  }
  return null;
}

/// A show the catalog no longer lists under the same id: its time and place.
Showtime _bare(String movie, String cinema, DateTime start) {
  final wall = cairoWallClock(start);
  // A show after midnight belongs to the evening before, as cinemas list it.
  final day = wall.hour < 5 ? wall.subtract(const Duration(days: 1)) : wall;
  return Showtime(
    cinemaId: cinema,
    movieId: movie,
    businessDate: day.toIso8601String().substring(0, 10),
    startsAt: start,
    wallClock: wall,
    format: '',
  );
}

/// The showtimes a notification announced: each film's shows first seen in
/// its window, at its cinemas, still to come. Shows the catalog doesn't know
/// (a cinema or film added since it loaded) are left out.
Future<List<Showtime>> fetchNews(
  AlertNews news,
  CatalogData catalog, {
  required Set<String> myCinemas,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final where = {for (final f in news.films) f.movieId: f.cinemas};
    // The cinemas the news is about, so the database sends only those rows:
    // a big notification's films can have thousands of new shows elsewhere.
    final cinemas = <String>{
      for (final f in news.films) ...(f.cinemas ?? myCinemas),
    };
    final everywhere =
        news.films.any((f) => f.cinemas == null) && myCinemas.isEmpty;
    final rows = await _rows(
      c,
      news,
      news.films.map((f) => f.movieId).toSet(),
      everywhere ? null : cinemas,
    );
    bool usable(Map<String, dynamic> s) =>
        catalog.cinemas.containsKey(s['cinema_id']) &&
        catalog.movies.containsKey(s['movie_id']);
    final kept = [
      for (final s in rows)
        if (usable(s) &&
            _at(where[s['movie_id']], myCinemas, s['cinema_id'] as String))
          s,
    ];
    // A film with nothing at those cinemas still shows its new shows from
    // anywhere, rather than none: the cinema list can be missing or out of
    // date, the shows are what was announced.
    final covered = {for (final s in kept) s['movie_id'] as String};
    final missing = {
      for (final f in news.films)
        if (!covered.contains(f.movieId)) f.movieId,
    };
    if (missing.isNotEmpty && !everywhere) {
      kept.addAll((await _rows(c, news, missing, null)).where(usable));
    }
    kept.sort(
      (a, b) => (a['starts_at'] as String).compareTo(b['starts_at'] as String),
    );
    return [for (final s in kept) _showtime(s)];
  } finally {
    if (client == null) c.close();
  }
}

/// Every new, upcoming show of [movies] in the news's window, at [cinemas]
/// (any when null), a page at a time: the database answers 1000 rows at most.
Future<List<Map<String, dynamic>>> _rows(
  http.Client c,
  AlertNews news,
  Set<String> movies,
  Set<String>? cinemas,
) async {
  String iso(DateTime t) => t.toUtc().toIso8601String();
  const page = 1000;
  final rows = <Map<String, dynamic>>[];
  for (var from = 0; from < 20000; from += page) {
    final uri =
        Uri.parse(
          '${SupabaseShowtimesRepository.url}/rest/v1/showtimes',
        ).replace(
          // A list value repeats the key: first_seen_at gets both bounds.
          queryParameters: {
            'select':
                'cinema_id,movie_id,business_date,starts_at,format,booking_url,price_egp',
            'movie_id': 'in.(${movies.join(',')})',
            if (cinemas != null) 'cinema_id': 'in.(${cinemas.join(',')})',
            'first_seen_at': [
              'gte.${iso(news.since)}',
              'lt.${iso(news.until)}',
            ],
            'starts_at': 'gt.${iso(DateTime.now())}',
            'order': 'starts_at,cinema_id,movie_id',
            'limit': '$page',
            'offset': '$from',
          },
        );
    final res = await c
        .get(uri, headers: SupabaseShowtimesRepository.headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode} ${res.body}');
    }
    final batch = (jsonDecode(utf8.decode(res.bodyBytes)) as List)
        .cast<Map<String, dynamic>>();
    rows.addAll(batch);
    if (batch.length < page) break;
  }
  return rows;
}

/// Whether a show at [cinemaId] belongs to the news: at the cinemas the
/// notification named, or else at the phone's own (any, if it has none).
bool _at(List<String>? named, Set<String> mine, String cinemaId) {
  if (named != null) return named.contains(cinemaId);
  return mine.isEmpty || mine.contains(cinemaId);
}

Showtime _showtime(Map<String, dynamic> s) {
  final startsAt = DateTime.parse(s['starts_at'] as String);
  return Showtime(
    cinemaId: s['cinema_id'] as String,
    movieId: s['movie_id'] as String,
    businessDate: s['business_date'] as String,
    startsAt: startsAt,
    wallClock: cairoWallClock(startsAt),
    format: s['format'] as String,
    bookingUrl: s['booking_url'] as String?,
    priceEgp: s['price_egp'] as int?,
  );
}
