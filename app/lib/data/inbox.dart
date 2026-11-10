import 'dart:convert';

import 'package:http/http.dart' as http;

import 'alert_news.dart';
import 'supabase_repository.dart';

/// One notification this phone was sent, as the inbox lists it.
class InboxEntry {
  const InboxEntry({required this.sentAt, required this.news});

  final DateTime sentAt;

  /// What it was about; opens the same "what's new" screen a tap does.
  final AlertNews news;
}

/// The notifications this phone was sent in the last two weeks, newest first
/// (Supabase `my_notifications`, from the pipeline's notification log). A
/// digest is one notification about several films.
Future<List<InboxEntry>> fetchInbox(String token, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .post(
          Uri.parse(
            '${SupabaseShowtimesRepository.url}/rest/v1/rpc/my_notifications',
          ),
          headers: {
            ...SupabaseShowtimesRepository.headers,
            'Content-Profile': 'shebbak',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'p_token': token}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode} ${res.body}');
    }
    final rows = (jsonDecode(utf8.decode(res.bodyBytes)) as List)
        .cast<Map<String, dynamic>>();
    return inboxFromRows(rows);
  } finally {
    if (client == null) c.close();
  }
}

/// Log rows (one per film) grouped back into the notifications they made.
List<InboxEntry> inboxFromRows(List<Map<String, dynamic>> rows) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    (groups['${r['run_at']}|${r['title']}'] ??= []).add(r);
  }
  final entries = [
    for (final g in groups.values)
      if (g.first['movie_id'] != null)
        () {
          final sentAt = DateTime.parse(g.first['run_at'] as String);
          final since = g.first['since'] as String?;
          return InboxEntry(
            sentAt: sentAt,
            news: AlertNews(
              films: [
                for (final r in g)
                  NewsFilm(
                    movieId: r['movie_id'] as String,
                    kind: NewsKind.values.firstWhere(
                      (k) => k.name == r['kind'],
                      // A digest's rows say "digest": new shows, then.
                      orElse: () => NewsKind.shows,
                    ),
                    cinemas: (r['cinemas'] as List?)?.cast<String>(),
                  ),
              ],
              // Notifications sent before the log kept the window: the
              // hour before, which is how often the pipeline checks.
              since: since != null
                  ? DateTime.parse(since)
                  : sentAt.subtract(const Duration(hours: 1)),
              until: sentAt,
              title: g.first['title'] as String?,
              body: g.first['body'] as String?,
            ),
          );
        }(),
  ];
  entries.sort((a, b) => b.sentAt.compareTo(a.sentAt));
  return entries;
}
