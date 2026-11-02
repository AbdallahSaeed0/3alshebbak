import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/models.dart';

/// Premiere Cinemas' showtimes, read on the phone when a film page opens.
///
/// Premiere's site turns our servers away, but it's an ordinary website to a
/// phone: this loads its now-showing page in a hidden web view, the way a
/// visitor's browser would, and reads the times with the same page script the
/// scraper uses (assets/premiere/premiere.page.js, which clicks cinema → date →
/// format like a visitor). Phones only; one page per app session.
class PremiereLive {
  PremiereLive._();
  static final instance = PremiereLive._();

  static bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static const _nowShowing = 'https://www.premiere-cinemas.com/en/now-showing';

  /// Today plus elCinema's week plus two months of presales.
  static const _daysAhead = 67;

  HeadlessInAppWebView? _view;
  InAppWebViewController? _page;
  Future<List<PremiereListing>>? _listing;
  final _results = <String, Future<PremiereShows>>{};

  /// The page clicks through one film at a time.
  Future<void> _turn = Future.value();

  /// [movie]'s shows at Premiere, from [today]. Empty when Premiere doesn't
  /// list it or the site can't be read; a failure is retried on the next call.
  Future<PremiereShows> showtimesFor(Movie movie, String today) {
    if (!available) return Future.value(PremiereShows.none);
    return _results[movie.id] ??= _load(movie, today).catchError((Object e) {
      debugPrint('Premiere showtimes for ${movie.title}: $e');
      _results.remove(movie.id);
      return PremiereShows.none;
    });
  }

  Future<PremiereShows> _load(Movie movie, String today) async {
    final listing = await (_listing ??= _open().catchError((Object e) {
      _listing = null;
      throw e;
    }));
    final match = listing.where((l) => l.matches(movie)).firstOrNull;
    if (match == null || match.cinemas.isEmpty) return PremiereShows.none;

    final dates = [
      for (var i = 0; i < _daysAhead; i++) addDays(today, i),
    ];
    final days = await _serially(() async {
      final result = await _page!
          .callAsyncJavaScript(
            functionBody: 'return await window.__shebbakPremiere.crawl(job);',
            arguments: {
              'job': {'movieId': match.id, 'dates': dates},
            },
          )
          .timeout(const Duration(minutes: 2));
      if (result?.error != null) throw Exception(result!.error);
      return (result?.value as Map?) ?? const {};
    });
    return premiereShows(movieId: movie.id, bookingUrl: match.url, days: days);
  }

  Future<T> _serially<T>(Future<T> Function() task) {
    final run = _turn.then((_) => task());
    _turn = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<List<PremiereListing>> _open() async {
    final script = await rootBundle.loadString(
      'assets/premiere/premiere.page.js',
    );
    final loaded = Completer<void>();
    _view = HeadlessInAppWebView(
      // Wide enough for the site's desktop layout, which the page script reads.
      initialSize: const Size(1280, 900),
      initialUrlRequest: URLRequest(url: WebUri(_nowShowing)),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: script,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (c) => _page = c,
      onLoadStop: (_, _) {
        if (!loaded.isCompleted) loaded.complete();
      },
    );
    await _view!.run();
    await loaded.future.timeout(const Duration(seconds: 45));

    // A first visit can get a browser check that reloads the page; the
    // script is injected again then, so ask once more after a pause.
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await _page!
          .callAsyncJavaScript(
            functionBody: 'return await window.__shebbakPremiere.ready();',
          )
          .timeout(const Duration(seconds: 70));
      if (result?.error == null && result?.value is List) {
        return [
          for (final l in result!.value as List)
            PremiereListing.fromJson(Map<String, dynamic>.from(l as Map)),
        ];
      }
      lastError = result?.error;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw Exception('Premiere page never got ready: $lastError');
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
    url: j['url'] as String? ?? 'https://www.premiere-cinemas.com/en/now-showing',
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

/// "The Avengers: Doomsday!" and "Avengers - Doomsday" read the same.
String normalizeTitle(String title) => title
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'^the\s+'), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// What Premiere showed for one film: its shows, and Premiere branches the
/// catalog may not have (the app's own cinemas list covers the rest).
class PremiereShows {
  const PremiereShows(this.showtimes, this.cinemas);
  static const none = PremiereShows([], {});

  final List<Showtime> showtimes;
  final Map<String, Cinema> cinemas;
}

/// Premiere branch names → the cinema the server already lists them under
/// (elCinema's). Branches not here are Premiere's alone (premiere:<slug>).
const _listedBranches = {
  'Premiere Plaza': 'elcinema:americana-plaza',
  'Premiere Point90': 'elcinema:premiere-point90',
  'Cima Arkan': 'elcinema:cima-arkan',
};

String _slug(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Turns the page script's `{ "yyyy-mm-dd": [{ name, formats: [{ name, times }] }] }`
/// into showtimes.
PremiereShows premiereShows({
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
      final cinemaId = _listedBranches[name] ?? 'premiere:${_slug(name)}';
      if (!_listedBranches.containsKey(name)) {
        cinemas[cinemaId] = Cinema(
          id: cinemaId,
          chain: 'Premiere',
          name: name,
          url: 'https://www.premiere-cinemas.com',
        );
      }
      for (final f in (branch['formats'] as List? ?? const [])) {
        final format = Map<String, dynamic>.from(f as Map);
        for (final t in (format['times'] as List? ?? const [])) {
          final show = premiereShowtime(
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
  return PremiereShows(shows, cinemas);
}

/// "2D · PREMIUM" → "Standard", as elCinema names the same halls; "2D · MX4D" → "MX4D".
String premiereFormat(String name) {
  final parts = [
    for (final p in name.split('·').map((p) => p.trim()))
      if (p.isNotEmpty && p != '2D')
        if (p.toLowerCase() == 'premium')
          'Standard'
        else if (RegExp(r'^[A-Z]{4,}$').hasMatch(p) && p != 'IMAX')
          p[0] + p.substring(1).toLowerCase()
        else
          p,
  ];
  return parts.isEmpty ? 'Standard' : parts.join(' · ');
}

/// Shows before 6 AM belong to the schedule day before (as on the server).
const _businessDayStartHour = 6;

/// A show on [businessDate] at [clock] ("10:30 PM", "12:15 AM"), in Cairo time.
Showtime? premiereShowtime({
  required String movieId,
  required String cinemaId,
  required String businessDate,
  required String clock,
  required String format,
  String? bookingUrl,
}) {
  final m = RegExp(
    r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?',
  ).firstMatch(clock);
  final day = DateTime.tryParse(businessDate);
  if (m == null || day == null) return null;
  var hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  final ampm = m.group(3)?.toLowerCase();
  if (ampm == 'pm' && hour < 12) hour += 12;
  if (ampm == 'am' && hour == 12) hour = 0;

  final wall = DateTime(
    day.year,
    day.month,
    day.day + (hour < _businessDayStartHour ? 1 : 0),
    hour,
    minute,
  );
  final startsAt = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  ).subtract(Duration(hours: cairoUtcOffsetHours(wall)));
  return Showtime(
    cinemaId: cinemaId,
    movieId: movieId,
    businessDate: businessDate,
    startsAt: startsAt,
    wallClock: wall,
    format: format,
    bookingUrl: bookingUrl,
  );
}

/// Egypt's clocks: +3 in summer time (last Friday of April to last Thursday of
/// October, since 2023), +2 otherwise.
int cairoUtcOffsetHours(DateTime wall) {
  // Calendar math in UTC: the phone's own zone may have a DST jump in between.
  DateTime lastWeekday(int year, int month, int weekday) {
    var d = DateTime.utc(year, month + 1, 0);
    while (d.weekday != weekday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  final at = DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute);
  final start = lastWeekday(wall.year, 4, DateTime.friday);
  final end = lastWeekday(
    wall.year,
    10,
    DateTime.thursday,
  ).add(const Duration(days: 1));
  return !at.isBefore(start) && at.isBefore(end) ? 3 : 2;
}

String addDays(String isoDate, int days) {
  final d = DateTime.utc(
    int.parse(isoDate.substring(0, 4)),
    int.parse(isoDate.substring(5, 7)),
    int.parse(isoDate.substring(8, 10)),
  ).add(Duration(days: days));
  return d.toIso8601String().substring(0, 10);
}
