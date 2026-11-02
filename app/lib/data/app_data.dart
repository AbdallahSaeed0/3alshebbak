import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../util/format.dart';
import '../util/search.dart';
import 'models.dart';
import 'prefs.dart';
import 'repository.dart';

/// Cairo time. Egypt observes DST (since 2023): last Friday of April to the
/// last Thursday of October at +03:00, +02:00 the rest of the year.
DateTime cairoWallClock(DateTime instant) {
  final utc = instant.toUtc();
  final plusTwo = utc.add(const Duration(hours: 2));
  final y = plusTwo.year;
  DateTime lastWeekday(int month, int weekday) {
    var d = DateTime.utc(y, month + 1, 0);
    while (d.weekday != weekday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  final dstStart = lastWeekday(4, DateTime.friday);
  final dstEnd = lastWeekday(
    10,
    DateTime.thursday,
  ).add(const Duration(days: 1));
  final inDst = !plusTwo.isBefore(dstStart) && plusTwo.isBefore(dstEnd);
  final local = inDst ? utc.add(const Duration(hours: 3)) : plusTwo;
  // Strip the UTC flag: this is a wall-clock reading, not an instant.
  return DateTime(local.year, local.month, local.day, local.hour, local.minute);
}

String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One movie's showings on a day, for the "showing today" list.
class MovieDay {
  MovieDay(this.movie, this.showtimes, this.cinemaCount);
  final Movie movie;

  /// Upcoming ones only, earliest first.
  final List<Showtime> showtimes;
  final int cinemaCount;
}

/// A movie whose schedule starts on a later day — a pre-booking.
class Upcoming {
  Upcoming(this.movie, this.firstDate, this.cinemas);
  final Movie movie;
  final String firstDate;
  final List<Cinema> cinemas;
}

/// A movie in a browse list: how widely it's showing.
class MovieSummary {
  MovieSummary(this.movie, this.cinemaCount, this.showCount);
  final Movie movie;
  final int cinemaCount;
  final int showCount;
}

/// Everything the screens ask of the data, in one place.
class AppData {
  AppData(this.catalog, this.prefs, {DateTime? now})
    : now = now ?? _clockFor(catalog);

  final CatalogData catalog;
  final Prefs prefs;
  final DateTime now;

  /// Fetches the latest showtimes (pull to refresh); set by the app.
  Future<void> Function()? refresh;

  /// Experience filters offered in Explore, matched against each chain's format names.
  static const formatFilters = [
    'IMAX',
    '4DX',
    'ScreenX',
    'MX4D',
    'DBOX',
    'VIP',
    'Gold',
  ];

  Set<String> get myCinemaIds => prefs.myCinemas;

  /// Real time — unless the bundled data is already in the past (it's a
  /// snapshot until Supabase is connected), then the evening of its first day.
  static DateTime _clockFor(CatalogData catalog) {
    final real = DateTime.now();
    if (catalog.showtimes.isEmpty ||
        catalog.showtimes.last.startsAt.isAfter(real))
      return real;
    final first = catalog.showtimes.first.businessDate;
    return DateTime.parse('${first}T18:45:00+02:00');
  }

  DateTime get cairoNow => cairoWallClock(now);

  /// Before 6 AM it's still last night's schedule.
  String get today => isoDate(cairoNow.subtract(const Duration(hours: 6)));

  /// A cinema only a phone-read source mentions (premiere:<slug>) gets a name
  /// from its id rather than failing.
  Cinema cinema(String id) =>
      catalog.cinemas[id] ??
      Cinema(
        id: id,
        chain: id.startsWith('premiere:') ? 'Premiere' : 'Independent',
        name: id
            .substring(id.indexOf(':') + 1)
            .split('-')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' '),
      );
  Movie movie(String id) => catalog.movies[id]!;

  /// What Home shows: my cinemas, or every cinema in the city picked there.
  bool _onHome(Showtime s) {
    final city = prefs.homeCity;
    return city == null
        ? prefs.isMine(s.cinemaId)
        : catalog.cinemas[s.cinemaId]?.city == city;
  }

  /// How many cinemas Home covers.
  int get homeCinemaCount {
    final city = prefs.homeCity;
    return city == null
        ? prefs.myCinemas.where(catalog.cinemas.containsKey).length
        : catalog.cinemas.values.where((c) => c.city == city).length;
  }

  /// Cities with cinemas and how many, most first.
  List<(String, int)> get cities {
    final counts = <String, int>{};
    for (final c in catalog.cinemas.values) {
      if (c.city case final city?) counts[city] = (counts[city] ?? 0) + 1;
    }
    return [for (final e in counts.entries) (e.key, e.value)]
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// What's next at my cinemas — whatever city Home shows: each film's next
  /// show at each of them within [window], soonest first.
  List<Showtime> nextAtMyCinemas({
    Duration window = const Duration(hours: 24),
    int limit = 20,
  }) {
    final until = now.add(window);
    final seen = <String>{};
    final list = [
      for (final s in catalog.showtimes)
        if (s.startsAt.isAfter(now) &&
            !s.startsAt.isAfter(until) &&
            prefs.isMine(s.cinemaId) &&
            seen.add('${s.movieId}|${s.cinemaId}'))
          s,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return list.take(limit).toList();
  }

  /// Movies with shows still to come today on Home, busiest first.
  List<MovieDay> showingToday() {
    final byMovie = <String, List<Showtime>>{};
    for (final s in catalog.showtimes) {
      if (s.businessDate == today && s.startsAt.isAfter(now) && _onHome(s)) {
        (byMovie[s.movieId] ??= []).add(s);
      }
    }
    final days = [
      for (final e in byMovie.entries)
        MovieDay(
          movie(e.key),
          e.value,
          e.value.map((s) => s.cinemaId).toSet().length,
        ),
    ];
    days.sort((a, b) => b.showtimes.length.compareTo(a.showtimes.length));
    return days;
  }

  /// Movies whose first show anywhere is after today, by first date.
  /// [maxDaysAhead] splits "tickets just opened" (this week) from "coming soon".
  List<Upcoming> upcoming({
    required int minDaysAhead,
    required int maxDaysAhead,
  }) {
    final first = <String, String>{};
    final cinemas = <String, Set<String>>{};
    for (final s in catalog.showtimes) {
      final d = first[s.movieId];
      if (d == null || s.businessDate.compareTo(d) < 0)
        first[s.movieId] = s.businessDate;
    }
    for (final s in catalog.showtimes) {
      if (s.businessDate == first[s.movieId])
        (cinemas[s.movieId] ??= {}).add(s.cinemaId);
    }
    final todayDate = DateTime.parse(today);
    final list = [
      for (final e in first.entries)
        if (_daysBetween(todayDate, DateTime.parse(e.value)) case final days
            when days >= minDaysAhead && days <= maxDaysAhead)
          Upcoming(movie(e.key), e.value, cinemas[e.key]!.map(cinema).toList()),
    ];
    list.sort((a, b) => a.firstDate.compareTo(b.firstDate));
    return list;
  }

  static int _daysBetween(DateTime a, DateTime b) =>
      b.difference(a).inHours ~/ 24;

  bool _upcoming(Showtime s) =>
      s.startsAt.isAfter(now) && s.businessDate.compareTo(today) >= 0;

  /// Schedule days still ahead for a movie and/or cinema, earliest first.
  /// [extra] are shows read on the phone (Premiere's, see premiere_live.dart).
  List<String> dates({
    String? movieId,
    String? cinemaId,
    List<Showtime> extra = const [],
  }) {
    final days = <String>{
      for (final s in [...catalog.showtimes, ...extra])
        if ((movieId == null || s.movieId == movieId) &&
            (cinemaId == null || s.cinemaId == cinemaId) &&
            _upcoming(s))
          s.businessDate,
    };
    return days.toList()..sort();
  }

  /// A movie's shows on [date], per cinema: my cinemas first, then by name.
  /// [extra] shows read on the phone fill in cinemas the catalog has nothing
  /// for that day; where it has the day, the catalog wins. [extraCinemas]
  /// names cinemas only they mention.
  List<(Cinema, List<Showtime>)> movieSchedule(
    String movieId,
    String date, {
    List<Showtime> extra = const [],
    Map<String, Cinema> extraCinemas = const {},
  }) {
    final byCinema = <String, List<Showtime>>{};
    for (final s in catalog.showtimes) {
      if (s.movieId == movieId && s.businessDate == date && _upcoming(s))
        (byCinema[s.cinemaId] ??= []).add(s);
    }
    final listed = byCinema.keys.toSet();
    for (final s in extra) {
      final known =
          catalog.cinemas.containsKey(s.cinemaId) ||
          extraCinemas.containsKey(s.cinemaId);
      if (s.movieId == movieId &&
          s.businessDate == date &&
          _upcoming(s) &&
          known &&
          !listed.contains(s.cinemaId))
        (byCinema[s.cinemaId] ??= []).add(s);
    }
    final list = [
      for (final e in byCinema.entries)
        (catalog.cinemas[e.key] ?? extraCinemas[e.key]!, e.value),
    ];
    list.sort((a, b) {
      final mine =
          (prefs.isMine(b.$1.id) ? 1 : 0) - (prefs.isMine(a.$1.id) ? 1 : 0);
      return mine != 0 ? mine : a.$1.label.compareTo(b.$1.label);
    });
    return list;
  }

  /// A cinema's shows on [date], per movie, busiest first.
  List<(Movie, List<Showtime>)> cinemaSchedule(String cinemaId, String date) {
    final byMovie = <String, List<Showtime>>{};
    for (final s in catalog.showtimes) {
      if (s.cinemaId == cinemaId && s.businessDate == date && _upcoming(s))
        (byMovie[s.movieId] ??= []).add(s);
    }
    final list = [for (final e in byMovie.entries) (movie(e.key), e.value)];
    list.sort((a, b) => b.$2.length.compareTo(a.$2.length));
    return list;
  }

  /// Movies with shows in the coming week, filtered, most widely showing first.
  List<MovieSummary> nowShowing({
    String query = '',
    String? format,
    bool mineOnly = false,
  }) {
    final weekEnd = isoDate(DateTime.parse(today).add(const Duration(days: 7)));
    final q = SearchQuery(query);
    final cinemas = <String, Set<String>>{};
    final shows = <String, int>{};
    for (final s in catalog.showtimes) {
      if (!_upcoming(s) || s.businessDate.compareTo(weekEnd) > 0) continue;
      if (mineOnly && !prefs.isMine(s.cinemaId)) continue;
      if (format != null &&
          !s.format.toLowerCase().contains(format.toLowerCase()))
        continue;
      (cinemas[s.movieId] ??= {}).add(s.cinemaId);
      shows[s.movieId] = (shows[s.movieId] ?? 0) + 1;
    }
    final list = [
      for (final e in cinemas.entries)
        if (movieMatches(movie(e.key), q))
          MovieSummary(movie(e.key), e.value.length, shows[e.key]!),
    ];
    list.sort(
      (a, b) => b.cinemaCount != a.cinemaCount
          ? b.cinemaCount.compareTo(a.cinemaCount)
          : b.showCount.compareTo(a.showCount),
    );
    return list;
  }

  /// By any of its titles, Arabic or English, or its genre.
  static bool movieMatches(Movie m, SearchQuery q) =>
      q.matches([m.title, m.titleAr, m.originalTitle, ...m.genres]);

  /// By name (either language), chain, area or city.
  static bool cinemaMatches(Cinema c, SearchQuery q) => q.matches([
    c.label,
    c.nameAr,
    c.chain,
    if (c.area != null) ...[c.area, areaNameAr(c.area!)],
    if (c.city != null) ...[c.city, cityNameAr(c.city!)],
  ]);

  /// All cinemas: mine first, then by city and name.
  List<Cinema> cinemas({String query = ''}) {
    final q = SearchQuery(query);
    final list = [
      for (final c in catalog.cinemas.values)
        if (cinemaMatches(c, q)) c,
    ];
    list.sort((a, b) {
      final mine = (prefs.isMine(b.id) ? 1 : 0) - (prefs.isMine(a.id) ? 1 : 0);
      if (mine != 0) return mine;
      final city = (a.city ?? '~').compareTo(b.city ?? '~');
      return city != 0 ? city : a.label.compareTo(b.label);
    });
    return list;
  }

  /// Straight-line distance from where the user last was, when we know both.
  double? distanceKm(Cinema c) {
    final spot = prefs.spot;
    if (spot == null || !c.hasLocation) return null;
    return haversineKm(spot.lat, spot.lng, c.lat!, c.lng!);
  }

  /// Cinemas by distance from [spot], nearest first; ones without a pin last.
  List<Cinema> byDistance(Spot spot) {
    double d(Cinema c) => c.hasLocation
        ? haversineKm(spot.lat, spot.lng, c.lat!, c.lng!)
        : double.infinity;
    return catalog.cinemas.values.toList()
      ..sort((a, b) => d(a).compareTo(d(b)));
  }

  Showtime? nextShow({String? cinemaId, String? movieId}) {
    for (final s in catalog.showtimes) {
      if ((cinemaId == null || s.cinemaId == cinemaId) &&
          (movieId == null || s.movieId == movieId) &&
          _upcoming(s)) {
        return s;
      }
    }
    return null;
  }
}

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Hands [AppData] to every screen below it, and rebuilds them when the
/// user's picks (their cinemas, followed films) change.
class AppScope extends InheritedNotifier<Prefs> {
  AppScope({super.key, required this.data, required super.child})
    : super(notifier: data.prefs);

  final AppData data;

  static AppData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.data;

  /// Also when fresh showtimes arrive (a new [AppData]), not only when the
  /// user's picks change.
  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.data != data || super.updateShouldNotify(oldWidget);
}
