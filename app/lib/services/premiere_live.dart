import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/models.dart';
import 'hidden_page.dart';
import 'live_shows.dart';
import 'live_source.dart';

/// Premiere Cinemas' showtimes, read on the phone when a film page opens.
///
/// Premiere's site turns our servers away, but it's an ordinary website to a
/// phone: this keeps its now-showing page open in a hidden web view and reads
/// times with the same page script the scraper uses
/// (assets/premiere/premiere.page.js, which clicks cinema → date → format like
/// a visitor).
class PremiereLive extends LiveSource {
  PremiereLive._() : super('premiere');
  static final instance = PremiereLive._();

  static const _nowShowing = 'https://www.premiere-cinemas.com/en/now-showing';

  /// Today plus elCinema's week plus two months of presales.
  static const _daysAhead = 67;

  Future<(HiddenPage, List<PremiereListing>)>? _site;

  @override
  void warmUp() {
    if (HiddenPage.available) unawaited(_open().then((_) {}, onError: (_) {}));
  }

  Future<(HiddenPage, List<PremiereListing>)> _open() => _site ??= () async {
    final started = DateTime.now();
    try {
      final page = await HiddenPage.open(
        _nowShowing,
        script: await rootBundle.loadString('assets/premiere/premiere.page.js'),
      );
      // A first visit can get a browser check that reloads the page; the
      // script is injected again then, so ask once more after a pause.
      for (var attempt = 0; ; attempt++) {
        try {
          final value = await page.call(
            'return await window.__shebbakPremiere.ready({ all: false });',
            timeout: const Duration(seconds: 70),
          );
          final listing = [
            for (final l in value as List)
              PremiereListing.fromJson(Map<String, dynamic>.from(l as Map)),
          ];
          debugPrint(
            'premiere: page ready in ${DateTime.now().difference(started).inMilliseconds} ms',
          );
          return (page, listing);
        } catch (e) {
          if (attempt > 0) {
            await page.close();
            rethrow;
          }
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    } catch (e) {
      _site = null;
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
    final (page, listing) = await _open();
    final match = listing.where((l) => l.matches(movie)).firstOrNull;
    // Its branches may not have loaded yet (ready() didn't wait); crawl() waits.
    if (match == null) return LiveShows.none;

    final dates = [for (var i = 0; i < _daysAhead; i++) addDays(today, i)];
    // Days the server already has at a branch it lists (elCinema's week).
    final skip = <String, List<String>>{
      for (final MapEntry(key: branch, value: cinemaId)
          in _listedBranches.entries)
        branch: [
          for (final d in dates)
            if (known.contains('$cinemaId|$d')) d,
        ],
    };
    // Each branch-day is sent back as soon as it's read, so the nearest days
    // show while the clicking goes on.
    final soFar = <String, List<Map<String, dynamic>>>{};
    const channel = 'premiereDay';
    page.listen(channel, (args) {
      if (args.isEmpty || args.first is! Map) return;
      final day = Map<String, dynamic>.from(args.first as Map);
      (soFar[day['date'] as String] ??= []).add(day);
      partial(
        premiereShows(movieId: movie.id, bookingUrl: match.url, days: soFar),
      );
    });
    try {
      final days = await page.call(
        'return await window.__shebbakPremiere.crawl(job);',
        args: {
          'job': {
            'movieId': match.id,
            'dates': dates,
            'skip': skip,
            'progress': channel,
          },
        },
      );
      return premiereShows(
        movieId: movie.id,
        bookingUrl: match.url,
        days: (days as Map?) ?? const {},
      );
    } finally {
      page.stopListening(channel);
    }
  }
}

/// A film on Premiere's now-showing page.
class PremiereListing {
  const PremiereListing({
    required this.id,
    required this.title,
    required this.cinemas,
    required this.url,
  });

  factory PremiereListing.fromJson(Map<String, dynamic> j) => PremiereListing(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    cinemas: [for (final c in (j['cinemas'] as List? ?? const [])) '$c'],
    url:
        j['url'] as String? ??
        'https://www.premiere-cinemas.com/en/now-showing',
  );

  final String id;
  final String title;
  final List<String> cinemas;
  final String url;

  /// Premiere lists films by their English title.
  bool matches(Movie movie) {
    final mine = normalizeTitle(title);
    return mine.isNotEmpty &&
        (normalizeTitle(movie.title) == mine ||
            (movie.originalTitle != null &&
                normalizeTitle(movie.originalTitle!) == mine));
  }
}

/// Premiere branch names → the cinema the server already lists them under
/// (elCinema's). Branches not here are Premiere's alone (premiere:<slug>).
const _listedBranches = {
  'Premiere Plaza': 'elcinema:americana-plaza',
  'Premiere Point90': 'elcinema:premiere-point90',
  'Cima Arkan': 'elcinema:cima-arkan',
};

/// Turns the page script's `{ "yyyy-mm-dd": [{ name, formats: [{ name, times }] }] }`
/// into showtimes.
LiveShows premiereShows({
  required String movieId,
  required String bookingUrl,
  required Map<dynamic, dynamic> days,
}) {
  final shows = <Showtime>[];
  final cinemas = <String, Cinema>{};
  for (final MapEntry(key: date, value: branches) in days.entries) {
    for (final b in (branches as List? ?? const [])) {
      final branch = Map<String, dynamic>.from(b as Map);
      final name = branch['name'] as String? ?? '';
      final cinemaId = _listedBranches[name] ?? 'premiere:${slugOf(name)}';
      if (!_listedBranches.containsKey(name)) {
        cinemas[cinemaId] = Cinema(id: cinemaId, chain: 'Premiere', name: name);
      }
      for (final f in (branch['formats'] as List? ?? const [])) {
        final format = Map<String, dynamic>.from(f as Map);
        for (final t in (format['times'] as List? ?? const [])) {
          final show = liveShowtime(
            movieId: movieId,
            cinemaId: cinemaId,
            businessDate: '$date',
            clock: '$t',
            format: premiereFormat(format['name'] as String? ?? ''),
            bookingUrl: bookingUrl,
          );
          if (show != null) shows.add(show);
        }
      }
    }
  }
  shows.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return LiveShows(shows, cinemas);
}

/// "2D · PREMIUM" → "Standard", as elCinema names the same halls; "2D · MX4D" → "MX4D".
String premiereFormat(String name) {
  final parts = [
    for (final p in name.split('·').map((p) => p.trim()))
      if (p.isNotEmpty && p != '2D')
        p.toLowerCase() == 'premium' ? 'Standard' : hallName(p),
  ];
  return parts.isEmpty ? 'Standard' : parts.join(' · ');
}
