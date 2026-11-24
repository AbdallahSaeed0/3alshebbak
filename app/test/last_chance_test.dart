import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/app_data.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/data/prefs.dart';
import 'package:shebbak/data/repository.dart';

Showtime _show(String movie, String day, {String cinema = 'scene:cfc'}) =>
    Showtime(
      cinemaId: cinema,
      movieId: movie,
      businessDate: day,
      startsAt: DateTime.parse('${day}T18:00:00Z'),
      wallClock: DateTime.parse('${day}T20:00:00'),
      format: 'Standard',
    );

/// [films] each showing on every one of [days] at [cinema].
List<Showtime> _program(
  List<String> films,
  List<String> days, {
  String cinema = 'scene:cfc',
}) => [
  for (final f in films)
    for (final d in days) _show(f, d, cinema: cinema),
];

AppData _data(List<Showtime> shows, {Set<String>? mine}) => AppData(
  CatalogData(
    cinemas: {
      for (final id in ['scene:cfc', 'vox:moe'])
        id: Cinema(id: id, chain: 'Scene', name: id),
    },
    movies: {
      for (final s in shows) s.movieId: Movie(id: s.movieId, title: s.movieId),
    },
    showtimes: shows,
  ),
  Prefs.memory(cinemas: mine ?? {'scene:cfc'}),
  // Monday 23 Nov, morning in Cairo.
  now: DateTime.parse('2026-11-23T07:00:00Z'),
);

const _thisWeek = ['2026-11-23', '2026-11-24', '2026-11-25'];
const _nextWeek = ['2026-11-26', '2026-11-27', '2026-11-28'];

void main() {
  test('a film missing from the next week is leaving', () {
    final data = _data([
      ..._program(['a', 'b', 'going'], _thisWeek),
      ..._program(['a', 'b'], _nextWeek),
    ]);
    final leaving = data.lastChance();
    expect(leaving.map((l) => l.movie.id), ['going']);
    expect(leaving.single.lastDate, '2026-11-25');
  });

  test('the end of what is listed so far is not leaving', () {
    // Next week isn't out yet: every film stops on the same day.
    final data = _data(_program(['a', 'b', 'c'], _thisWeek));
    expect(data.lastChance(), isEmpty);
  });

  test("a couple of presale films weeks ahead don't make the rest leave", () {
    final data = _data([
      ..._program(['a', 'b', 'c', 'd'], _thisWeek),
      ..._program(['big-film'], ['2026-12-20', '2026-12-21']),
    ]);
    expect(data.lastChance(), isEmpty);
  });

  test('still on at another of my cinemas: not last chance', () {
    final data = _data(
      [
        ..._program(['a', 'b', 'x'], _thisWeek),
        ..._program(['a', 'b'], _nextWeek),
        ..._program(
          ['x', 'y'],
          [..._thisWeek, ..._nextWeek],
          cinema: 'vox:moe',
        ),
      ],
      mine: {'scene:cfc', 'vox:moe'},
    );
    expect(data.lastChance(), isEmpty);
  });

  test('only within the next few days, soonest first', () {
    final data = _data([
      ..._program(
        ['a', 'b', 'c', 'd'],
        [..._thisWeek, ..._nextWeek, '2026-12-05'],
      ),
      ..._program(['soon'], ['2026-11-24']),
      ..._program(['later'], ['2026-11-26']),
      ..._program(['far'], ['2026-12-01']),
    ]);
    expect(data.lastChance(withinDays: 4).map((l) => l.movie.id), [
      'soon',
      'later',
    ]);
  });
}
