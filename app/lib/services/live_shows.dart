import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';

/// Shows a phone read off a cinema's own site (premiere_live.dart,
/// vox_live.dart), and cinemas only they mention.
class LiveShows {
  const LiveShows(this.showtimes, this.cinemas);
  static const none = LiveShows([], {});

  final List<Showtime> showtimes;
  final Map<String, Cinema> cinemas;

  bool get isEmpty => showtimes.isEmpty;

  LiveShows plus(LiveShows other) => LiveShows(
    [...showtimes, ...other.showtimes],
    {...cinemas, ...other.cinemas},
  );

  Map<String, dynamic> toJson() => {
    'showtimes': [
      for (final s in showtimes)
        {
          'cinemaId': s.cinemaId,
          'businessDate': s.businessDate,
          'start': cairoIso(s.wallClock),
          'format': s.format,
          'bookingUrl': s.bookingUrl,
        },
    ],
    'cinemas': [
      for (final c in cinemas.values)
        {'id': c.id, 'chain': c.chain, 'name': c.name},
    ],
  };

  factory LiveShows.fromJson(Map<String, dynamic> j, String movieId) =>
      LiveShows(
        [
          for (final s in j['showtimes'] as List)
            Showtime.fromJson(Map<String, dynamic>.from(s as Map), movieId),
        ],
        {
          for (final c in j['cinemas'] as List)
            (c as Map)['id'] as String: Cinema(
              id: c['id'] as String,
              chain: c['chain'] as String,
              name: c['name'] as String,
            ),
        },
      );
}

/// Read shows kept on the phone, so a film opened again shows them at once
/// while they're read afresh behind.
class LiveCache {
  LiveCache._(this._dir);

  static const maxAge = Duration(hours: 12);
  static Future<LiveCache?>? _opening;

  static Future<LiveCache?> open() => _opening ??= () async {
    if (kIsWeb) return null;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/live-shows');
      await dir.create(recursive: true);
      return LiveCache._(dir);
    } catch (e) {
      debugPrint('No live-shows cache: $e');
      return null;
    }
  }();

  @visibleForTesting
  factory LiveCache.at(Directory dir) => LiveCache._(dir);

  final Directory _dir;

  File _file(String source, String movieId) => File(
    '${_dir.path}/$source-${movieId.replaceAll(RegExp(r'[^\w.-]'), '_')}.json',
  );

  Future<LiveShows?> read(
    String source,
    String movieId, {
    DateTime? now,
  }) async {
    try {
      final file = _file(source, movieId);
      if (!await file.exists()) return null;
      final saved =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final at = DateTime.parse(saved['savedAt'] as String);
      if ((now ?? DateTime.now()).difference(at) > maxAge) return null;
      return LiveShows.fromJson(
        Map<String, dynamic>.from(saved['shows'] as Map),
        movieId,
      );
    } catch (e) {
      debugPrint('Live-shows cache unreadable: $e');
      return null;
    }
  }

  Future<void> write(
    String source,
    String movieId,
    LiveShows shows, {
    DateTime? now,
  }) async {
    try {
      final file = _file(source, movieId);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'savedAt': (now ?? DateTime.now()).toIso8601String(),
          'movieId': movieId,
          'shows': shows.toJson(),
        }),
      );
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('Live-shows cache not written: $e');
    }
  }

  /// Films read in the last [within] (opened, or refreshed since), newest first.
  Future<List<String>> recentMovies({
    Duration within = const Duration(days: 7),
    DateTime? now,
  }) async {
    final since = (now ?? DateTime.now()).subtract(within);
    final found = <String, DateTime>{};
    try {
      await for (final f in _dir.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final saved =
              jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          final id = saved['movieId'] as String?;
          final at = DateTime.parse(saved['savedAt'] as String);
          if (id != null &&
              at.isAfter(since) &&
              (found[id]?.isBefore(at) ?? true)) {
            found[id] = at;
          }
        } catch (_) {
          // A half-written or old file: skip it.
        }
      }
    } catch (e) {
      debugPrint('Live-shows cache unlistable: $e');
    }
    return found.keys.toList()..sort((a, b) => found[b]!.compareTo(found[a]!));
  }
}

/// "2026-12-16T22:30:00+02:00" for a Cairo wall-clock time.
String cairoIso(DateTime wall) {
  final offset = cairoUtcOffsetHours(wall);
  final local = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  );
  return '${local.toIso8601String().substring(0, 19)}+0$offset:00';
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

  final at = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  );
  final start = lastWeekday(wall.year, 4, DateTime.friday);
  final end = lastWeekday(
    wall.year,
    10,
    DateTime.thursday,
  ).add(const Duration(days: 1));
  return !at.isBefore(start) && at.isBefore(end) ? 3 : 2;
}

/// Shows before 6 AM belong to the schedule day before (as on the server).
const _businessDayStartHour = 6;

/// A show on [businessDate] at [clock] ("10:30 PM", "12:15am"), in Cairo time.
Showtime? liveShowtime({
  required String movieId,
  required String cinemaId,
  required String businessDate,
  required String clock,
  required String format,
  String? bookingUrl,
}) {
  final m = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?').firstMatch(clock);
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
  return Showtime.fromJson({
    'cinemaId': cinemaId,
    'businessDate': businessDate,
    'start': cairoIso(wall),
    'format': format,
    'bookingUrl': bookingUrl,
  }, movieId);
}

/// Some chains shout hall names ("GOLD", "PREMIUM"); elCinema writes them
/// "Gold". Acronyms stay.
String hallName(String name) {
  final n = name.trim().isEmpty ? 'Standard' : name.trim();
  return RegExp(r'^[A-Z]{4,}$').hasMatch(n) && n != 'IMAX'
      ? n[0] + n.substring(1).toLowerCase()
      : n;
}

/// "The Avengers: Doomsday!" and "Avengers - Doomsday" read the same.
String normalizeTitle(String title) => title
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'^the\s+'), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

String slugOf(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

String addDays(String isoDate, int days) {
  final d = DateTime.utc(
    int.parse(isoDate.substring(0, 4)),
    int.parse(isoDate.substring(5, 7)),
    int.parse(isoDate.substring(8, 10)),
  ).add(Duration(days: days));
  return d.toIso8601String().substring(0, 10);
}

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// "Wed 16 Dec" → the next such date on or after [today] (yyyy-mm-dd); sites
/// give no year.
String? dayFromLabel(String label, String today) {
  final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})').firstMatch(label);
  final month = m == null ? -1 : _months.indexOf(m.group(2)!.toLowerCase());
  if (m == null || month < 0) return null;
  final year = int.parse(today.substring(0, 4));
  String iso(int y) =>
      '$y-${'${month + 1}'.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
  return iso(year).compareTo(addDays(today, -7)) >= 0
      ? iso(year)
      : iso(year + 1);
}
