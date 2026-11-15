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
      if (listing.isEmpty)
        throw Exception('no films on VOX\'s what\'s-on page');
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

  /// [s]'s VOX session id ("0047-278379"), read from the film's page for its
  /// day: same cinema and start, and when two formats start together, the
  /// one whose hall heading the show's format names. Null when it isn't there.
  Future<String?> sessionOf(Showtime s, Movie movie) async {
    final booked = RegExp(
      r'/booking/(\d{4}-\d+)',
    ).firstMatch(s.bookingUrl ?? '');
    if (booked != null) return booked.group(1);
    final day = s.businessDate.replaceAll('-', '');
    final candidates = <({String id, String heading})>[];
    for (final film in (await _films()).where((l) => l.matches(movie))) {
      final doc = await _get('/movies/${film.slug}?d=$day');
      String? cinemaId;
      for (final el in doc.querySelectorAll('#showtimes .dates > *')) {
        if (el.localName == 'h3') {
          cinemaId = _listedCinemas[el.text.trim()];
        } else if (cinemaId == s.cinemaId && el.classes.contains('showtimes')) {
          for (final li in el.children) {
            final heading = li.querySelector('strong')?.text.trim() ?? '';
            for (final a in li.querySelectorAll('a.showtime')) {
              final id = a.attributes['data-id'];
              final at = liveShowtime(
                movieId: movie.id,
                cinemaId: s.cinemaId,
                businessDate: s.businessDate,
                clock: a.text.trim(),
                format: heading,
              );
              if (id != null && at?.startsAt == s.startsAt) {
                candidates.add((id: id, heading: heading));
              }
            }
          }
        }
      }
    }
    if (candidates.length == 1) return candidates.single.id;
    final format = s.format.toUpperCase();
    final named = candidates
        .where((c) => format.contains(c.heading.toUpperCase()))
        .toList();
    return named.length == 1 ? named.single.id : null;
  }

  /// The hall a VOX session is in ("CINEMA 7"), from its booking page as a
  /// guest: VOX hands the visitor on through a few redirects, each setting
  /// cookies the next needs. A fresh set of cookies each time (VOX adds one
  /// per booking opened, and a long-kept set grows too big to send).
  Future<String?> screenOf(String session) async {
    final cookies = <String, String>{};
    var url = Uri.parse('$_origin/booking/$session');
    for (var hop = 0; hop < 10; hop++) {
      final req = http.Request('GET', url)
        ..followRedirects = false
        ..headers.addAll(_headers);
      if (cookies.isNotEmpty) {
        req.headers['Cookie'] = [
          for (final e in cookies.entries) '${e.key}=${e.value}',
        ].join('; ');
      }
      final res = await http.Response.fromStream(
        await _client.send(req),
      ).timeout(const Duration(seconds: 15));
      for (final c in _setCookies(res.headers['set-cookie'])) {
        cookies[c.$1] = c.$2;
      }
      final location = res.headers['location'];
      if (res.statusCode ~/ 100 == 3) {
        if (location == null || location.contains('/booking/error')) {
          return null;
        }
        url = url.resolve(location);
        continue;
      }
      if (res.statusCode != 200) return null;
      final screen = RegExp(
        r'<strong>Screen</strong>:\s*([^<]+)',
      ).firstMatch(res.body);
      if (screen != null) return screen.group(1)!.trim();
      // Still being prepared: ask again in a moment.
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }
}

/// `name=value` of each cookie in a Set-Cookie header (dart:io joins several
/// with commas, which an Expires date also contains).
List<(String, String)> _setCookies(String? header) => [
  for (final m in RegExp(
    r'(?:^|,\s*)([^=;,\s]+)=([^;,]*)',
  ).allMatches(header ?? ''))
    if (!const {
      'expires',
      'path',
      'domain',
      'max-age',
      'samesite',
    }.contains(m.group(1)!.toLowerCase()))
      (m.group(1)!, m.group(2)!),
];

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
typedef VoxCinema = ({
  String name,
  List<({String hall, List<String> times})> halls,
});

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

/// The VOX cinemas, as the server lists them.
Iterable<String> get voxCinemaIds => _listedCinemas.values;

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
  required List<(VoxListing, VoxFilmPage, List<(String, List<VoxCinema>)>)>
  films,
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
            format: film.experience == null
                ? hall
                : '$hall · ${film.experience}',
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
      add(
        '${ymd.substring(0, 4)}-${ymd.substring(4, 6)}-${ymd.substring(6)}',
        onDay,
        film,
      );
    }
  }
  shows.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return LiveShows(shows, cinemas);
}
