import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/alert_news.dart';
import 'package:shebbak/data/inbox.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/data/repository.dart';

RecentNews _news(String at, String movie, String kind, List<String> cinemas) =>
    RecentNews(
      at: DateTime.parse(at),
      since: DateTime.parse(at).subtract(const Duration(minutes: 30)),
      movieId: movie,
      kind: kind,
      cinemas: cinemas,
    );

final _catalog = CatalogData(
  cinemas: {
    for (final id in ['a', 'b', 'c'])
      id: Cinema(
        // Listed by elCinema, so labelled by its Arabic name alone.
        id: 'elcinema:$id',
        chain: 'Independent',
        name: 'Cinema $id',
        nameAr: 'سينما $id',
      ),
  },
  movies: {
    for (final id in ['tmdb:1', 'tmdb:2', 'tmdb:3'])
      id: Movie(id: id, title: 'Film $id'),
  },
  showtimes: const [],
  news: [
    // One run: three films at once (a digest for "every film" phones).
    _news('2026-11-09T02:23:00Z', 'tmdb:1', 'shows', ['a', 'b']),
    _news('2026-11-09T02:23:00Z', 'tmdb:2', 'opened', ['a']),
    _news('2026-11-09T02:23:00Z', 'tmdb:3', 'days', ['c']),
    // A later run about a film I follow, at a cinema I didn't pick.
    _news('2026-11-09T10:23:00Z', 'tmdb:1', 'shows', ['c']),
    // A film the catalog no longer has.
    _news('2026-11-09T11:00:00Z', 'tmdb:gone', 'shows', ['a']),
  ],
);

void main() {
  test('every film at my cinemas: one entry per run, newest first', () {
    final entries = inboxFromNews(
      _catalog,
      everyFilm: true,
      following: const {},
      allCinemas: false,
      myCinemas: {'a', 'b'},
    );
    expect(entries.length, 1, reason: 'the 10:23 run was at cinema c only');
    final run = entries.single.news;
    expect(run.films.map((f) => f.movieId), ['tmdb:1', 'tmdb:2']);
    expect(run.films.first.cinemas, ['a', 'b']);
    expect(run.films.last.kind, NewsKind.opened);
    expect(run.title, '🎬 مواعيد جديدة لـفيلمين');
  });

  test('only followed films, from every cinema', () {
    final entries = inboxFromNews(
      _catalog,
      everyFilm: false,
      following: {'tmdb:1'},
      allCinemas: true,
      myCinemas: {'a'},
    );
    expect(entries.map((e) => e.sentAt.hour), [10, 2]);
    expect(entries.first.news.title, '🕐 «Film tmdb:1»: حفلات جديدة');
    expect(entries.first.news.body, 'في سينما c');
    expect(entries.last.news.body, 'في سينما a وسينما كمان');
    expect(entries.first.news.since, DateTime.utc(2026, 11, 9, 9, 53));
  });

  test('nothing followed and no every-film: an empty page', () {
    expect(
      inboxFromNews(
        _catalog,
        everyFilm: false,
        following: const {},
        allCinemas: true,
        myCinemas: const {},
      ),
      isEmpty,
    );
  });
}
