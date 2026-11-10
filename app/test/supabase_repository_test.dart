import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shebbak/data/repository.dart';
import 'package:shebbak/data/supabase_repository.dart';
import 'package:shebbak/util/format.dart';

Map<String, dynamic> _show(int i) => {
  'cinema_id': 'scene:cfc',
  'movie_id': 'tmdb:1',
  'business_date': '2026-11-01',
  // 17:30 UTC = 7:30 PM in Cairo (+02:00 in November).
  'starts_at': '2026-11-01T17:30:00+00:00',
  'format': 'IMAX #$i',
  'booking_url': null,
  'price_egp': 250,
};

void main() {
  test('reads every page of showtimes and shows them in Cairo time', () async {
    const total = 1500;
    final pagesAsked = <String>[];
    final client = MockClient((req) async {
      final path = req.url.path.split('/').last;
      if (path == 'catalog.json') return http.Response('not found', 404);
      if (path == 'cinemas') {
        return http.Response(
          jsonEncode([
            {
              'id': 'scene:cfc',
              'chain': 'Scene',
              'name': 'Cairo Festival City',
            },
          ]),
          200,
        );
      }
      if (path == 'movies') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {'id': 'tmdb:1', 'title': 'Clayface', 'title_ar': 'كلايفيس'},
            ]),
          ),
          200,
        );
      }
      final range = req.headers['Range']!;
      pagesAsked.add(range);
      final from = int.parse(range.split('-').first);
      final to = int.parse(range.split('-').last).clamp(0, total - 1);
      return http.Response(
        jsonEncode([for (var i = from; i <= to; i++) _show(i)]),
        200,
        headers: {'content-range': '$from-$to/$total'},
      );
    });

    final data = await SupabaseShowtimesRepository(client: client).load();
    expect(pagesAsked, ['0-999', '1000-1999']);
    expect(data.showtimes.length, total);
    final s = data.showtimes.first;
    expect('${clock(s.wallClock)} ${period(s.wallClock)}', '7:30 م');
    expect(data.movies['tmdb:1']!.displayTitle, 'كلايفيس');
  });

  test(
    'falls back to the bundled snapshot when Supabase is unreachable',
    () async {
      final offline = SupabaseShowtimesRepository(
        client: MockClient((_) async => throw Exception('no network')),
      );
      final snapshot = CatalogData(cinemas: {}, movies: {}, showtimes: []);
      final repo = FallbackShowtimesRepository(offline, _Fixed(snapshot));
      expect(identical(await repo.load(), snapshot), isTrue);
    },
  );

  test('opens from the one-file snapshot when it is fresh', () async {
    final asked = <String>[];
    final client = MockClient((req) async {
      asked.add(req.url.path.split('/').last);
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'generatedAt': DateTime.now().toUtc().toIso8601String(),
            'cinemas': [
              {
                'id': 'scene:cfc',
                'chain': 'Scene',
                'name': 'Cairo Festival City',
              },
            ],
            'movies': [
              {'id': 'tmdb:1', 'title': 'Clayface', 'title_ar': 'كلايفيس'},
            ],
            'showtimes': [_show(0), _show(1)],
          }),
        ),
        200,
      );
    });
    final data = await SupabaseShowtimesRepository(client: client).load();
    expect(asked, ['catalog.json']); // one request, no database pages
    expect(data.showtimes.length, 2);
    expect(data.movies['tmdb:1']!.titleAr, 'كلايفيس');
  });

  test('a stale snapshot falls back to the database', () async {
    final asked = <String>[];
    final client = MockClient((req) async {
      final path = req.url.path.split('/').last;
      asked.add(path);
      if (path == 'catalog.json') {
        return http.Response(
          jsonEncode({
            'v': 1,
            'generatedAt': '2026-01-01T00:00:00Z',
            'cinemas': [],
            'movies': [],
            'showtimes': [],
          }),
          200,
        );
      }
      if (path == 'cinemas') {
        return http.Response(
          jsonEncode([
            {
              'id': 'scene:cfc',
              'chain': 'Scene',
              'name': 'Cairo Festival City',
            },
          ]),
          200,
        );
      }
      if (path == 'movies') {
        return http.Response(
          jsonEncode([
            {'id': 'tmdb:1', 'title': 'Clayface'},
          ]),
          200,
        );
      }
      return http.Response(
        jsonEncode([_show(0)]),
        200,
        headers: {'content-range': '0-0/1'},
      );
    });
    final data = await SupabaseShowtimesRepository(client: client).load();
    expect(asked.first, 'catalog.json');
    expect(asked, containsAll(['cinemas', 'movies', 'showtimes']));
    expect(data.showtimes.length, 1);
  });
}

class _Fixed implements ShowtimesRepository {
  _Fixed(this.data);
  final CatalogData data;
  @override
  Future<CatalogData> load() async => data;
}
