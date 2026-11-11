import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shebbak/data/alert_news.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/data/repository.dart';

Cinema _cinema(String id) => Cinema(id: id, chain: 'Premiere', name: id);

final _catalog = CatalogData(
  cinemas: {
    for (final id in ['a', 'b', 'c']) id: _cinema(id),
  },
  movies: {
    'tmdb:1': const Movie(id: 'tmdb:1', title: 'Avengers: Doomsday'),
    'tmdb:2': const Movie(id: 'tmdb:2', title: 'Hope'),
  },
  showtimes: const [],
);

Map<String, dynamic> _row(String movie, String cinema) => {
  'cinema_id': cinema,
  'movie_id': movie,
  'business_date': '2026-12-20',
  'starts_at': '2026-12-20T17:30:00+00:00',
  'format': 'Standard',
  'booking_url': null,
  'price_egp': null,
};

void main() {
  test('reads what a notification was about', () {
    final news = AlertNews.fromData({
      'type': 'alert',
      'movieId': 'tmdb:1',
      'films':
          '[{"m":"tmdb:1","k":"days","c":["a"]},{"m":"tmdb:2","k":"opened"}]',
      'since': '2026-11-09T02:23:00.000Z',
      'until': '2026-11-09T10:23:00.000Z',
    }, title: '🕐 «Avengers: Doomsday»: حفلات جديدة')!;
    expect(news.films.map((f) => f.movieId), ['tmdb:1', 'tmdb:2']);
    expect(news.films[0].kind, NewsKind.days);
    expect(news.films[0].cinemas, ['a']);
    expect(news.films[1].cinemas, isNull);
    expect(news.until.isAfter(news.since), isTrue);
    expect(news.title, contains('Avengers'));
  });

  test('older notifications and update notices are not news', () {
    expect(AlertNews.fromData({'movieId': 'tmdb:1'}), isNull);
    expect(AlertNews.fromData({'type': 'update', 'url': 'x'}), isNull);
    expect(AlertNews.fromData({'type': 'alert', 'films': 'not json'}), isNull);
  });

  test(
    'fetches the window and keeps the cinemas each film was news at',
    () async {
      Uri? asked;
      final client = MockClient((req) async {
        asked = req.url;
        return http.Response(
          jsonEncode([
            _row('tmdb:1', 'a'), // named cinema: kept
            _row('tmdb:1', 'b'), // not named for this film: dropped
            _row('tmdb:2', 'b'), // no cinemas named: the phone's own, kept
            _row('tmdb:2', 'c'), // not one of the phone's: dropped
            _row('tmdb:2', 'zzz'), // unknown to the catalog: dropped
          ]),
          200,
        );
      });
      final news = AlertNews(
        films: const [
          NewsFilm(movieId: 'tmdb:1', kind: NewsKind.shows, cinemas: ['a']),
          NewsFilm(movieId: 'tmdb:2', kind: NewsKind.opened),
        ],
        since: DateTime.utc(2026, 11, 9, 2, 23),
        until: DateTime.utc(2026, 11, 9, 10, 23),
      );
      final shows = await fetchNews(
        news,
        _catalog,
        myCinemas: {'a', 'b'},
        client: client,
      );
      expect(shows.map((s) => '${s.movieId}@${s.cinemaId}'), [
        'tmdb:1@a',
        'tmdb:2@b',
      ]);
      expect(asked!.queryParametersAll['first_seen_at'], [
        'gte.2026-11-09T02:23:00.000Z',
        'lt.2026-11-09T10:23:00.000Z',
      ]);
      expect(asked!.queryParameters['movie_id'], 'in.(tmdb:1,tmdb:2)');
    },
  );

  test(
    'a film with no shows at the named cinemas still shows its new ones',
    () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode([_row('tmdb:1', 'c')]), 200),
      );
      final news = AlertNews(
        films: const [
          NewsFilm(movieId: 'tmdb:1', kind: NewsKind.opened, cinemas: ['a']),
        ],
        since: DateTime.utc(2026, 11, 9),
        until: DateTime.utc(2026, 11, 10),
      );
      final shows = await fetchNews(
        news,
        _catalog,
        myCinemas: {'a'},
        client: client,
      );
      expect(shows.map((s) => '${s.movieId}@${s.cinemaId}'), ['tmdb:1@c']);
    },
  );
}
