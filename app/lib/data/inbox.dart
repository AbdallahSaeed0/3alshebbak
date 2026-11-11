import 'alert_news.dart';
import 'models.dart';
import 'repository.dart';

/// One notification in the inbox.
class InboxEntry {
  const InboxEntry({required this.sentAt, required this.news});

  final DateTime sentAt;

  /// What it was about; opens the same "what's new" screen a tap does.
  final AlertNews news;
}

/// What this phone's settings would have been told in the last two weeks,
/// newest first: the pipeline's announcements (the snapshot's `news`) for the
/// films it follows — or every film — at its cinemas — or every cinema. It
/// doesn't depend on this install's notification token, so the page isn't
/// empty after a reinstall or with notifications off. One alerts run makes
/// one entry, as it made one notification (or a digest) per phone.
List<InboxEntry> inboxFromNews(
  CatalogData catalog, {
  required bool everyFilm,
  required Set<String> following,
  required bool allCinemas,
  required Set<String> myCinemas,
}) {
  final everywhere = allCinemas || myCinemas.isEmpty;
  final runs = <DateTime, List<(RecentNews, List<String>)>>{};
  for (final n in catalog.news) {
    if (!catalog.movies.containsKey(n.movieId)) continue;
    if (!everyFilm && !following.contains(n.movieId)) continue;
    final at = everywhere
        ? n.cinemas
        : n.cinemas.where(myCinemas.contains).toList();
    if (at.isEmpty) continue;
    (runs[n.at] ??= []).add((n, at));
  }
  final entries = [
    for (final MapEntry(key: sentAt, value: items) in runs.entries)
      InboxEntry(
        sentAt: sentAt,
        news: AlertNews(
          films: [
            for (final (n, at) in items)
              NewsFilm(
                movieId: n.movieId,
                kind: NewsKind.values.firstWhere(
                  (k) => k.name == n.kind,
                  orElse: () => NewsKind.shows,
                ),
                cinemas: at,
              ),
          ],
          since:
              items.first.$1.since ?? sentAt.subtract(const Duration(hours: 1)),
          until: sentAt,
          title: _title(catalog, items),
          body: _body(catalog, items),
        ),
      ),
  ];
  entries.sort((a, b) => b.sentAt.compareTo(a.sentAt));
  return entries;
}

String _name(CatalogData c, String movieId) =>
    c.movies[movieId]?.displayTitle ?? movieId;

String _cinema(CatalogData c, String id) => c.cinemas[id]?.label ?? id;

/// As the notification put it (scraper/src/notify.ts: message, digest).
String _title(CatalogData c, List<(RecentNews, List<String>)> items) {
  if (items.length > 1) return '🎬 مواعيد جديدة لـ${_films(items.length)}';
  final (n, _) = items.single;
  final film = _name(c, n.movieId);
  return switch (n.kind) {
    'opened' => '🎟 تذاكر «$film» نزلت',
    'days' => '📅 «$film»: أيام حجز جديدة',
    _ => '🕐 «$film»: حفلات جديدة',
  };
}

String _body(CatalogData c, List<(RecentNews, List<String>)> items) {
  if (items.length > 1) {
    final names = items.take(2).map((i) => '«${_name(c, i.$1.movieId)}»');
    final rest = items.length - 2;
    return rest > 0
        ? '${names.join(' و')} و${_films(rest)} كمان'
        : names.join(' و');
  }
  final at = items.single.$2;
  final first = _cinema(c, at.first);
  final where = first.startsWith('سينما') ? first : 'سينما $first';
  return switch (at.length) {
    1 => 'في $where',
    2 => 'في $where وسينما كمان',
    _ => 'في $where و${at.length - 1} سينمات كمان',
  };
}

String _films(int n) => switch (n) {
  1 => 'فيلم',
  2 => 'فيلمين',
  <= 10 => '$n أفلام',
  _ => '$n فيلم',
};
