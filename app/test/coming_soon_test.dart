import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/app_data.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/data/prefs.dart';
import 'package:shebbak/data/repository.dart';

Showtime _show(String movie, String day) => Showtime(
  cinemaId: 'scene:cfc',
  movieId: movie,
  businessDate: day,
  startsAt: DateTime.parse('${day}T18:00:00Z'),
  wallClock: DateTime.parse('${day}T20:00:00'),
  format: 'Standard',
);

void main() {
  test('a film already showing is not "coming soon" late at night', () {
    final catalog = CatalogData(
      cinemas: {
        'scene:cfc': const Cinema(id: 'scene:cfc', chain: 'Scene', name: 'CFC'),
      },
      movies: {
        for (final id in ['tmdb:new', 'tmdb:running'])
          id: Movie(id: id, title: id),
      },
      // Tonight's shows are over: both films' next shows are tomorrow on.
      showtimes: [
        _show('tmdb:new', '2026-11-13'),
        _show('tmdb:running', '2026-11-13'),
      ],
      started: {'tmdb:running'},
    );
    final data = AppData(
      catalog,
      Prefs.memory(),
      now: DateTime.parse('2026-11-12T22:30:00Z'),
    );
    final soon = data.upcoming(minDaysAhead: 1, maxDaysAhead: 365);
    expect(soon.map((u) => u.movie.id), ['tmdb:new']);
  });
}
