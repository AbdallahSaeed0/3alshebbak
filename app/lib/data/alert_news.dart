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

/// The showtimes a notification announced: each film's shows first seen in
/// its window, at its cinemas, still to come. Shows the catalog doesn't know
/// (a cinema or film added since it loaded) are left out.
Future<List<Showtime>> fetchNews(
  AlertNews news,
  CatalogData catalog, {
  required Set<String> myCinemas,
  http.Client? client,
}) async {
  final ids = news.films.map((f) => f.movieId).toSet();
  String iso(DateTime t) => t.toUtc().toIso8601String();
  final uri = Uri.parse('${SupabaseShowtimesRepository.url}/rest/v1/showtimes')
      .replace(
        // A list value repeats the key: first_seen_at gets both bounds.
        queryParameters: {
          'select':
              'cinema_id,movie_id,business_date,starts_at,format,booking_url,price_egp',
          'movie_id': 'in.(${ids.join(',')})',
          'first_seen_at': ['gte.${iso(news.since)}', 'lt.${iso(news.until)}'],
          'starts_at': 'gt.${iso(DateTime.now())}',
          'order': 'starts_at',
          'limit': '2000',
        },
      );
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(uri, headers: SupabaseShowtimesRepository.headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode} ${res.body}');
    }
    final rows = (jsonDecode(utf8.decode(res.bodyBytes)) as List)
        .cast<Map<String, dynamic>>();
    final where = {for (final f in news.films) f.movieId: f.cinemas};
    final known = [
      for (final s in rows)
        if (catalog.cinemas.containsKey(s['cinema_id']) &&
            catalog.movies.containsKey(s['movie_id']))
          s,
    ];
    final kept = [
      for (final s in known)
        if (_at(where[s['movie_id']], myCinemas, s['cinema_id'] as String)) s,
    ];
    // A film whose new shows all fall outside the cinemas the notification
    // (or this phone) names still shows them, rather than none: the cinema
    // list can be missing or out of date, the shows are what was announced.
    final covered = {for (final s in kept) s['movie_id']};
    return [
      for (final s in known)
        if (kept.contains(s) || !covered.contains(s['movie_id'])) _showtime(s),
    ];
  } finally {
    if (client == null) c.close();
  }
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
