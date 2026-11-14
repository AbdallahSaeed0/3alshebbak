import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// One seat in a hall's grid. [col] counts every cell, gaps included, so
/// columns line up between rows; [depth] counts rows from the screen, aisle
/// rows included.
class Seat {
  const Seat({
    required this.row,
    required this.number,
    required this.col,
    required this.depth,
  });

  final String row;
  final String number;
  final int col;
  final int depth;

  String get label => '$row$number';
}

/// A hall's real seat layout, read once from the cinema's booking seat map
/// (scraper/data/halls.json, bundled as assets/halls/halls.json). Distances,
/// screen size and rake aren't on any seat map: they come from [geometry],
/// typical figures for the hall's kind.
class Hall {
  Hall({
    required this.cinemaId,
    required this.name,
    required this.formats,
    required this.seats,
    required this.columns,
    required this.depths,
    required this.rowNames,
    required this.prices,
    this.hallIds = const {},
    this.freeSeating = false,
  }) : geometry = HallGeometry.forFormats(formats);

  final String cinemaId;
  final String name;
  final List<String> formats;
  final List<Seat> seats;

  /// The ids a show's [Showtime.hall] can carry for this hall
  /// (`elcinema:<screen id>`, `rns:…`, `prm:<cinema>:<screen>`); one hall
  /// can be sold as two screens.
  final Set<String> hallIds;

  /// Tickets carry no seat (Zawya): the plan still shows where to sit.
  final bool freeSeating;

  /// Grid size: the widest row's cells, and rows front to back.
  final int columns;
  final int depths;

  /// Row letter at each depth ('' for an aisle row).
  final List<String> rowNames;
  final Map<String, int> prices;
  final HallGeometry geometry;

  static Hall fromJson(String cinemaId, Map<String, dynamic> j) {
    final seats = <Seat>[];
    final rowNames = <String>[];
    var columns = 0;
    final prices = <String, int>{};
    for (final section
        in (j['sections'] as List).cast<Map<String, dynamic>>()) {
      (section['prices'] as Map<String, dynamic>? ?? {}).forEach(
        (k, v) => prices[k] = (v as num).toInt(),
      );
      for (final line in (section['rows'] as List).cast<String>()) {
        final bar = line.indexOf('|');
        final row = line.substring(0, bar);
        final cells = line.substring(bar + 1).trim().split(RegExp(r'\s+'));
        final depth = rowNames.length;
        rowNames.add(row);
        columns = math.max(columns, cells.length);
        for (var c = 0; c < cells.length; c++) {
          if (cells[c] == '.' || cells[c].isEmpty) continue;
          seats.add(Seat(row: row, number: cells[c], col: c, depth: depth));
        }
      }
    }
    final screenIds = {
      if (j['elcinemaScreenId'] case final String id) id,
      ...((j['elcinemaScreenIds'] as List?) ?? const []).cast<String>(),
    };
    return Hall(
      cinemaId: cinemaId,
      name: j['name'] as String,
      formats: (j['formats'] as List).cast<String>(),
      seats: seats,
      columns: columns,
      depths: rowNames.length,
      rowNames: rowNames,
      prices: prices,
      hallIds: {
        for (final id in screenIds) 'elcinema:$id',
        // short on shows, to keep the catalog file small (renaissance.ts)
        if (j['rnsScreenId'] case final String id)
          'rns:${id.substring(id.length - 6)}',
        if (j['premiereScreenId'] case final String id) 'prm:$id',
      },
      freeSeating: j['freeSeating'] == true,
    );
  }

  // ---- Positions, in metres. x: right of the hall's centre line as you face
  // the screen; z: distance from the screen wall; y: height above the floor
  // at the front.

  double seatX(Seat s) => (s.col - (columns - 1) / 2) * geometry.seatWidth;
  double seatZ(Seat s) =>
      geometry.firstRowDistance + s.depth * geometry.rowDepth;
  double floorY(int depth) => depth * geometry.rise;
  double eyeY(Seat s) => floorY(s.depth) + 1.15;

  /// How it is to watch from [s].
  SeatView viewFrom(Seat s) {
    final g = geometry;
    final x = seatX(s), z = seatZ(s);
    final eye = eyeY(s);
    // Angle the screen's width takes up (as seen from straight in front of it).
    final width = 2 * math.atan((g.screenWidth / 2) / z) * 180 / math.pi;
    // How far to the side of the screen's centre.
    final side = math.atan(x.abs() / z) * 180 / math.pi;
    // Looking up at the screen's top edge.
    final up =
        math.atan((g.screenBottom + g.screenHeight - eye) / z) * 180 / math.pi;

    var score = 1.0;
    if (width < g.idealMin) score -= (g.idealMin - width) / 25;
    if (width > g.idealMax) score -= (width - g.idealMax) / 18;
    if (side > 15) score -= (side - 15) / 25;
    if (up > 30) score -= (up - 30) / 15;
    score = score.clamp(0.0, 1.0);

    final ViewIssue? issue;
    if (up > 32 || width > g.idealMax + 12) {
      issue = ViewIssue.tooClose;
    } else if (side > 22) {
      issue = ViewIssue.toTheSide;
    } else if (width < g.idealMin - 6) {
      issue = ViewIssue.farBack;
    } else if (width > g.idealMax) {
      issue = ViewIssue.close;
    } else if (width < g.idealMin) {
      issue = ViewIssue.aBitFar;
    } else {
      issue = null;
    }
    return SeatView(
      score: score,
      screenAngle: width,
      sideAngle: side,
      lookUp: up,
      issue: issue,
    );
  }

  /// The seat with the best view (the most central one on ties).
  Seat get bestSeat => seats.reduce((a, b) {
    final sa = viewFrom(a).score, sb = viewFrom(b).score;
    if ((sa - sb).abs() > 1e-6) return sa > sb ? a : b;
    return seatX(a).abs() <= seatX(b).abs() ? a : b;
  });
}

enum ViewIssue { tooClose, close, aBitFar, farBack, toTheSide }

class SeatView {
  const SeatView({
    required this.score,
    required this.screenAngle,
    required this.sideAngle,
    required this.lookUp,
    required this.issue,
  });

  /// 0 (poor) to 1 (as good as it gets in this hall).
  final double score;

  /// Degrees of your view the screen's width fills.
  final double screenAngle;

  /// Degrees off the screen's centre line.
  final double sideAngle;

  /// Degrees you look up to see the top of the screen.
  final double lookUp;
  final ViewIssue? issue;
}

/// What no seat map says: typical sizes for a kind of hall. The view is as
/// good as these guesses; the seats themselves are real.
class HallGeometry {
  const HallGeometry({
    required this.screenWidth,
    required this.aspect,
    required this.screenBottom,
    required this.firstRowDistance,
    required this.rowDepth,
    required this.seatWidth,
    required this.rise,
    required this.idealMin,
    required this.idealMax,
    this.curve = 0.3,
  });

  /// How far the screen's edges come towards the seats, in metres: big
  /// screens curve to wrap the view, IMAX's most.
  final double curve;

  final double screenWidth;
  final double aspect;
  final double screenBottom;
  final double firstRowDistance;
  final double rowDepth;
  final double seatWidth;

  /// How much each row is raised over the one in front (stadium seating).
  final double rise;

  /// The screen's width as an angle, in degrees, where viewing is best
  /// (cinema engineering guidance: about 36–45° for a normal hall; IMAX is
  /// built to fill more of your view).
  final double idealMin;
  final double idealMax;

  double get screenHeight => screenWidth / aspect;

  static HallGeometry forFormats(List<String> formats) {
    final f = formats.join(' ').toUpperCase();
    if (f.contains('IMAX')) {
      // Floor to ceiling, and curved round the seats.
      return const HallGeometry(
        screenWidth: 20,
        aspect: 1.9,
        screenBottom: 0.7,
        curve: 1.4,
        firstRowDistance: 5.5,
        rowDepth: 1.1,
        seatWidth: 0.56,
        rise: 0.38,
        idealMin: 48,
        idealMax: 68,
      );
    }
    if (f.contains('4D') || f.contains('MX4D') || f.contains('4DX')) {
      return const HallGeometry(
        screenWidth: 10,
        aspect: 2.0,
        screenBottom: 1.4,
        firstRowDistance: 5,
        rowDepth: 1.5,
        seatWidth: 0.75,
        rise: 0.5,
        idealMin: 38,
        idealMax: 55,
      );
    }
    return const HallGeometry(
      screenWidth: 12,
      aspect: 2.0,
      screenBottom: 1.3,
      firstRowDistance: 4.5,
      rowDepth: 1.05,
      seatWidth: 0.55,
      rise: 0.3,
      idealMin: 34,
      idealMax: 46,
    );
  }
}

/// The bundled hall layouts, loaded once.
class Halls {
  Halls._(this._byCinema);

  final Map<String, List<Hall>> _byCinema;

  static Halls? _loaded;

  /// Null until [load] finishes (or when the file is missing).
  static Halls? get instance => _loaded;

  static Future<void> load() async {
    if (_loaded != null) return;
    try {
      final json =
          jsonDecode(await rootBundle.loadString('assets/halls/halls.json'))
              as Map<String, dynamic>;
      _loaded = Halls.fromJson(json);
    } catch (e) {
      debugPrint('Hall layouts unavailable: $e');
    }
  }

  static Halls fromJson(Map<String, dynamic> json) => Halls._({
    for (final e in json.entries)
      if (!e.key.startsWith('_'))
        e.key: [
          for (final h
              in ((e.value as Map<String, dynamic>)['halls'] as List)
                  .cast<Map<String, dynamic>>())
            Hall.fromJson(e.key, h),
        ],
  });

  /// The hall a show is in, when the format says which: a cinema's IMAX or
  /// MX4D hall is the only one of its kind. Shows in a cinema's ordinary
  /// halls could be in any of them, so they get none.
  ///
  /// A format is matched part by part ("MX4D · 4DX" → MX4D, 4DX), whole, and
  /// with 2D/3D set aside ("IMAX 3D" → IMAX): so a MAX hall gets "MAX" shows
  /// but not "IMAX" or "MAX VIP" ones.
  ///
  /// A show that names its hall ([Showtime.hall], from elCinema's booking
  /// lookup) gets that hall, or none when its plan isn't recorded: the format
  /// can't tell a cinema's numbered halls apart.
  Hall? forShowtime(Showtime s) {
    final halls = _byCinema[s.cinemaId];
    if (halls == null) return null;
    if (s.hall case final hall?) {
      for (final h in halls) {
        if (h.hallIds.contains(hall)) return h;
      }
      return null;
    }
    final parts = formatParts(s.format);
    for (final h in halls) {
      if (h.formats.any((f) => parts.contains(f.toUpperCase()))) return h;
    }
    return null;
  }

  @visibleForTesting
  static Set<String> formatParts(String format) => {
    for (final p in format.toUpperCase().split(RegExp(r'[·|/,]')))
      if (p.replaceAll(RegExp(r'\b[23]D\b'), '').trim() case final part
          when part.isNotEmpty)
        part.replaceAll(RegExp(r'\s+'), ' '),
  };
}
