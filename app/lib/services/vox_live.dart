import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../data/models.dart';
import 'hidden_page.dart';
import 'live_shows.dart';
import 'live_source.dart';

/// VOX's showtimes for a film, read on the phone when its page opens.
///
/// The server gets VOX's week from elCinema and each presale's opening day
/// from VOX's film pages; the days in between are only on VOX's own site.
/// VOX answers plain requests from a client that says who it is (it stalls
/// ones posing as a browser), so this fetches the film's page for every day
/// directly, all at once, over one kept-open connection.
class VoxLive extends LiveSource {
  VoxLive._() : super('vox');
  static final instance = VoxLive._();

  static const _origin = 'https://egy.voxcinemas.com';
  static const _headers = {
    'User-Agent':
        '3alShebbak/0.1 (Android app; +https://github.com/AbdallahSaeed0/3alshebbak)',
    'Accept-Language': 'en',
  };

  final _client = http.Client();
  Future<List<VoxListing>>? _listing;

  @override
  void warmUp() {
    // Phones only: a browser would refuse the cross-site request.
    if (HiddenPage.available) unawaited(_films().then((_) {}, onError: (_) {}));
  }

  Future<dom.Document> _get(String path) async {
    final res = await _client
        .get(Uri.parse('$_origin$path'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('$path: HTTP ${res.statusCode}');
    return html.parse(res.body);
  }

  Future<List<VoxListing>> _films() => _listing ??= () async {
    final started = DateTime.now();
    try {
      final listing = voxListing(await _get('/movies/whatson'));
      if (listing.isEmpty) throw Exception('no films on VOX\'s what\'s-on page');
      debugPrint(
        'vox: listing in ${DateTime.now().difference(started).inMilliseconds} ms',
      );
      return listing;
    } catch (e) {
      _listing = null;
      rethrow;
    }
  }();

  @override
  Future<LiveShows> read(
    Movie movie,
    String today,
    Set<String> known,
    void Function(LiveShows) partial,
  ) async {
    final matches = (await _films()).where((l) => l.matches(movie)).toList();
    if (matches.isEmpty) return LiveShows.none;

    // Each film page shows one day, with links to the rest (`?d=yyyymmdd`).
    final films = await Future.wait(
      matches.map((m) async {
        final first = VoxFilmPage.parse(await _get('/movies/${m.slug}'));
        final rest = await Future.wait(
          first.otherDays.map(
            (d) async => (
              d,
              VoxFilmPage.parse(await _get('/movies/${m.slug}?d=$d')).cinemas,
            ),
          ),
        );
        return (m, first, rest);
      }),
    );
    return voxShows(movieId: movie.id, today: today, films: films);
  }
}

/// A film on VOX's what's-on page. "Avengers: Doomsday (Infinity Vision)" is
/// listed apart from the film; it's the same film in another format.
class VoxListing {
  VoxListing({required this.slug, required String title})
    : title = _base(title),
      experience = _experience(title);

  final String slug;
  final String title;
  final String? experience;

  static final _variant = RegExp(
    r'^(.*?)\s*\(([^)]*Vision[^)]*)\)\s*$',
    caseSensitive: false,
  );
  static String _base(String t) => _variant.firstMatch(t)?.group(1) ?? t;
  static String? _experience(String t) => _variant.firstMatch(t)?.group(2);

  bool matches(Movie movie) {
    final mine = normalizeTitle(title);
    return slug.isNotEmpty &&
        mine.isNotEmpty &&
        (normalizeTitle(movie.title) == mine ||
            (movie.originalTitle != null &&
                normalizeTitle(movie.originalTitle!) == mine));
  }
}

List<VoxListing> voxListing(dom.Document doc) => [
  for (final a in doc.querySelectorAll('article.movie-summary'))
    if (a.attributes['data-slug'] case final slug?)
      VoxListing(slug: slug, title: a.attributes['data-title'] ?? ''),
];

/// One cinema's halls and times on a VOX film page.
typedef VoxCinema = ({String name, List<({String hall, List<String> times})> halls});

/// A VOX film page: the day it shows, links to its other days, and the times.
class VoxFilmPage {
  const VoxFilmPage(this.shownLabel, this.otherDays, this.cinemas);

  /// The date tab without a link, e.g. "Wed 16 Dec".
  final String shownLabel;

  /// The other days on sale, as `yyyymmdd`.
  final List<String> otherDays;
  final List<VoxCinema> cinemas;

  factory VoxFilmPage.parse(dom.Document doc) {
    final days = <String>[
      for (final a in doc.querySelectorAll('nav.date-filter a'))
        if (RegExp(r'[?&]d=(\d{8})').firstMatch(a.attributes['href'] ?? '')
            case final m?)
          m.group(1)!,
    ];
    final cinemas = <VoxCinema>[];
    for (final el in doc.querySelectorAll('#showtimes .dates > *')) {
      if (el.localName == 'h3') {
        cinemas.add((name: el.text.trim(), halls: []));
      } else if (cinemas.isNotEmpty && el.classes.contains('showtimes')) {
        for (final li in el.children) {
          final times = [
            for (final a in li.querySelectorAll('a.showtime')) a.text.trim(),
          ];
          if (times.isNotEmpty) {
            cinemas.last.halls.add((
              hall: li.querySelector('strong')?.text.trim() ?? '',
              times: times,
            ));
          }
        }
      }
    }
    return VoxFilmPage(
      doc.querySelector('nav.date-filter li > span')?.text.trim() ?? '',
      days,
      cinemas,
    );
  }
}

/// VOX's cinema names → the cinema the server lists them under (elCinema's).
const _listedCinemas = {
  'City Centre Almaza': 'elcinema:city-centre-almaza',
  'Mall of Egypt': 'elcinema:mall-of-egypt',
  'City Centre Alexandria': 'elcinema:city-centre-alexandria',
};

/// Each matching listing's first page and its other days' cinemas → showtimes.
LiveShows voxShows({
  required String movieId,
  required String today,
  required List<(VoxListing, VoxFilmPage, List<(String, List<VoxCinema>)>)> films,
}) {
  final shows = <Showtime>[];
  final cinemas = <String, Cinema>{};

  void add(String? date, List<VoxCinema> onDay, VoxListing film) {
    if (date == null) return;
    for (final c in onDay) {
      final cinemaId = _listedCinemas[c.name] ?? 'vox:${slugOf(c.name)}';
      if (!_listedCinemas.containsKey(c.name)) {
        cinemas[cinemaId] = Cinema(id: cinemaId, chain: 'VOX', name: c.name);
      }
      for (final h in c.halls) {
        final hall = hallName(h.hall);
        for (final t in h.times) {
          final show = liveShowtime(
            movieId: movieId,
            cinemaId: cinemaId,
            businessDate: date,
            clock: t,
            format: film.experience == null ? hall : '$hall · ${film.experience}',
            bookingUrl: 'https://egy.voxcinemas.com/movies/${film.slug}',
          );
          if (show != null) shows.add(show);
        }
      }
    }
  }

  for (final (film, first, rest) in films) {
    add(dayFromLabel(first.shownLabel, today), first.cinemas, film);
    for (final (ymd, onDay) in rest) {
      add('${ymd.substring(0, 4)}-${ymd.substring(4, 6)}-${ymd.substring(6)}', onDay, film);
    }
  }
  shows.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return LiveShows(shows, cinemas);
}
