import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/alert_news.dart';
import 'package:shebbak/data/inbox.dart';

Map<String, dynamic> _row(
  String runAt,
  String movie,
  String kind,
  String title, {
  String? since,
}) => {
  'run_at': runAt,
  'since': since,
  'movie_id': movie,
  'kind': kind,
  'cinemas': ['elcinema:americana-plaza'],
  'title': title,
  'body': 'body of $title',
};

void main() {
  test('log rows group back into the notifications they made', () {
    final entries = inboxFromRows([
      // A digest: one notification, three films.
      for (final m in ['tmdb:1', 'tmdb:2', 'tmdb:3'])
        _row(
          '2026-11-09T02:23:00+00:00',
          m,
          'digest',
          'مواعيد جديدة لـ3 أفلام',
          since: '2026-11-09T01:23:00+00:00',
        ),
      // A newer notification for one film, from before `since` was logged.
      _row('2026-11-09T10:23:00+00:00', 'tmdb:9', 'shows', 'Avengers'),
    ]);

    expect(entries.length, 2);
    final avengers = entries.first; // newest first
    expect(avengers.news.title, 'Avengers');
    expect(avengers.news.films.single.kind, NewsKind.shows);
    expect(
      avengers.news.since,
      DateTime.utc(2026, 11, 9, 9, 23),
      reason: 'no window logged: the hour before',
    );

    final digest = entries.last;
    expect(digest.news.films.map((f) => f.movieId), [
      'tmdb:1',
      'tmdb:2',
      'tmdb:3',
    ]);
    expect(digest.news.since, DateTime.utc(2026, 11, 9, 1, 23));
    expect(digest.news.until, DateTime.utc(2026, 11, 9, 2, 23));
    expect(digest.news.films.first.cinemas, ['elcinema:americana-plaza']);
  });
}
