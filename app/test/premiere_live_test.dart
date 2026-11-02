import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/services/premiere_live.dart';

void main() {
  test('Premiere titles match the catalog\'s', () {
    const listing = PremiereListing(
      id: '5180.855',
      title: 'Avengers: Doomsday',
      cinemas: ['Nile Cinema'],
      url: 'https://www.premiere-cinemas.com/en/movie-details/5180.855/1',
    );
    expect(
      listing.matches(const Movie(id: 'tmdb:1', title: 'Avengers - Doomsday')),
      isTrue,
    );
    expect(
      listing.matches(const Movie(id: 'tmdb:2', title: 'Dune: Part Three')),
      isFalse,
    );
  });

  test('a page result becomes Cairo-time showtimes', () {
    final shows = premiereShows(
      movieId: 'tmdb:1',
      bookingUrl: 'https://example.test',
      days: {
        '2026-12-16': [
          {
            'name': 'Nile Cinema',
            'formats': [
              {
                'name': '2D · PREMIUM',
                'times': ['10:30 PM', '12:45 AM'],
              },
            ],
          },
          {
            'name': 'Premiere Point90',
            'formats': [
              {
                'name': '2D · MX4D',
                'times': ['04:00 PM'],
              },
            ],
          },
        ],
      },
    );
    expect(shows.showtimes, hasLength(3));
    expect(shows.cinemas.keys, ['premiere:nile-cinema']);

    final late = shows.showtimes.last;
    // 12:45 AM after the 16th's late show: still the 16th's schedule.
    expect(late.businessDate, '2026-12-16');
    expect(late.wallClock, DateTime(2026, 12, 17, 0, 45));
    expect(late.startsAt, DateTime.utc(2026, 12, 16, 22, 45));
    expect(late.format, 'Standard');
    expect(shows.showtimes.first.cinemaId, 'elcinema:premiere-point90');
    expect(shows.showtimes.first.format, 'MX4D');
  });

  test('Cairo is UTC+3 in summer time, +2 otherwise', () {
    expect(cairoUtcOffsetHours(DateTime(2026, 12, 16, 20)), 2);
    expect(cairoUtcOffsetHours(DateTime(2026, 7, 1, 20)), 3);
    // 2026: summer time from Friday 24 April through Thursday 29 October.
    expect(cairoUtcOffsetHours(DateTime(2026, 4, 23, 23)), 2);
    expect(cairoUtcOffsetHours(DateTime(2026, 4, 24, 1)), 3);
    expect(cairoUtcOffsetHours(DateTime(2026, 10, 29, 23)), 3);
    expect(cairoUtcOffsetHours(DateTime(2026, 10, 30, 1)), 2);
  });

  test('hall names read like elCinema writes them', () {
    expect(premiereFormat('2D · PREMIUM'), 'Standard');
    expect(premiereFormat('2D · LUXE'), 'Luxe');
    expect(premiereFormat('3D · IMAX'), '3D · IMAX');
  });
}
