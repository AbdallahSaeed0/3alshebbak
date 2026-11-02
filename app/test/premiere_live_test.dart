import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shebbak/data/models.dart';
import 'package:shebbak/services/live_shows.dart';
import 'package:shebbak/services/premiere_live.dart';
import 'package:shebbak/services/vox_live.dart';

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

  test('a Premiere page result becomes Cairo-time showtimes', () {
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

  test('VOX\'s Infinity Vision listing is the same film in another format', () {
    final plain = VoxListing(slug: 'avengers-doomsday', title: 'Avengers: Doomsday');
    final iv = VoxListing(
      slug: 'avengers-doomsday-infinity-vision',
      title: 'Avengers: Doomsday (Infinity Vision)',
    );
    const movie = Movie(id: 'tmdb:1', title: 'Avengers: Doomsday');
    expect(plain.matches(movie) && iv.matches(movie), isTrue);
    expect(iv.experience, 'Infinity Vision');

    // As VOX serves a film page (trimmed).
    final first = VoxFilmPage.parse(
      html.parse('''
<section id="showtimes">
  <nav class="date-filter"><ol>
    <li> <span>Wed 16 Dec</span> </li>
    <li> <a href="/movies/avengers-doomsday-infinity-vision?d&#x3D;20261217#showtimes">Thu 17 Dec</a> </li>
  </ol></nav>
  <div class="dates">
    <h3 class="highlight">Mall of Egypt</h3>
    <ol class="showtimes">
      <li> <strong>MAX</strong> <ol>
        <li><a class="action showtime" href="/booking/1">11:15am </a></li>
      </ol> </li>
    </ol>
  </div>
</section>'''),
    );
    expect(first.shownLabel, 'Wed 16 Dec');
    expect(first.otherDays, ['20261217']);

    final shows = voxShows(
      movieId: 'tmdb:1',
      today: '2026-11-02',
      films: [
        (
          iv,
          first,
          [
            (
              '20261217',
              <VoxCinema>[
                (
                  name: 'City Centre Almaza',
                  halls: [
                    (hall: 'GOLD', times: ['7:15pm']),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    expect(shows.showtimes, hasLength(2));
    expect(shows.showtimes.first.businessDate, '2026-12-16');
    expect(shows.showtimes.first.cinemaId, 'elcinema:mall-of-egypt');
    expect(shows.showtimes.first.format, 'MAX · Infinity Vision');
    expect(shows.showtimes.last.businessDate, '2026-12-17');
    expect(shows.showtimes.last.format, 'Gold · Infinity Vision');
    expect(shows.showtimes.last.wallClock, DateTime(2026, 12, 17, 19, 15));
  });

  test('read shows are kept on the phone for half a day', () async {
    final dir = await Directory.systemTemp.createTemp('live');
    addTearDown(() => dir.delete(recursive: true));
    final cache = LiveCache.at(dir);
    final shows = premiereShows(
      movieId: 'tmdb:1',
      bookingUrl: 'https://example.test',
      days: {
        '2026-12-16': [
          {
            'name': 'Nile Cinema',
            'formats': [
              {
                'name': '2D · LUXE',
                'times': ['10:30 PM'],
              },
            ],
          },
        ],
      },
    );
    final saved = DateTime(2026, 11, 2, 20);
    await cache.write('premiere', 'tmdb:1', shows, now: saved);

    final back = await cache.read('premiere', 'tmdb:1', now: saved.add(const Duration(hours: 1)));
    expect(back!.showtimes.single.startsAt, shows.showtimes.single.startsAt);
    expect(back.showtimes.single.format, 'Luxe');
    expect(back.cinemas['premiere:nile-cinema']!.name, 'Nile Cinema');
    expect(
      await cache.read('premiere', 'tmdb:1', now: saved.add(const Duration(hours: 13))),
      isNull,
    );
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

  test('day labels without a year, and hall names', () {
    expect(dayFromLabel('Wed 16 Dec', '2026-11-02'), '2026-12-16');
    expect(dayFromLabel('Mon 4 Jan', '2026-12-20'), '2027-01-04');
    expect(premiereFormat('2D · PREMIUM'), 'Standard');
    expect(premiereFormat('3D · IMAX'), '3D · IMAX');
    expect(hallName('GOLD'), 'Gold');
  });
}
