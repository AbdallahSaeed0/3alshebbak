import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/inbox.dart';
import '../services/push.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/schedule.dart';
import 'news_screen.dart';

void openNotifications(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

/// Every notification this phone got in the last two weeks; tapping one shows
/// what it was about, like tapping it when it arrived.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<InboxEntry>?> _entries = _load();

  /// Null when this phone has no notifications turned on.
  Future<List<InboxEntry>?> _load() async {
    final token = await Push.instance.currentToken();
    if (token == null) return null;
    return fetchInbox(token);
  }

  @override
  Widget build(BuildContext context) {
    final cairoNow = AppScope.of(context).cairoNow;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('الإشعارات', 'Notifications'),
          style: AppText.display(24),
        ),
        backgroundColor: AppColors.background,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _entries = _load());
          await _entries;
        },
        child: FutureBuilder<List<InboxEntry>?>(
          future: _entries,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snap.data;
            final String? message = snap.hasError
                ? tr(
                    'ما قدرناش نجيب الإشعارات دلوقتي. اسحب لتحت وجرّب تاني.',
                    'Couldn\'t load notifications. Pull down to try again.',
                  )
                : entries == null
                ? tr(
                    'الإشعارات مقفولة على الموبايل ده. شغّلها من الإعدادات وهتلاقي هنا كل جديد.',
                    'Notifications are off on this phone. Turn them on in Settings and they\'ll collect here.',
                  )
                : entries.isEmpty
                ? tr(
                    'مفيش إشعارات في آخر أسبوعين.',
                    'No notifications in the last two weeks.',
                  )
                : null;
            if (message != null) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppText.body(15, color: AppColors.muted),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              itemCount: entries!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _EntryCard(
                entry: entries[i],
                when: _when(entries[i].sentAt, cairoNow),
              ),
            );
          },
        ),
      ),
    );
  }

  /// "النهارده 4:23 م", "امبارح 9:10 ص", else the day.
  static String _when(DateTime sentAt, DateTime cairoNow) {
    final wall = cairoWallClock(sentAt);
    final day = DateTime(wall.year, wall.month, wall.day);
    final today = DateTime(cairoNow.year, cairoNow.month, cairoNow.day);
    final ago = today.difference(day).inDays;
    final label = switch (ago) {
      0 => tr('النهارده', 'Today'),
      1 => tr('امبارح', 'Yesterday'),
      _ => dayLabel(day.toIso8601String().substring(0, 10)),
    };
    return '$label ${clock(wall)} ${period(wall)}';
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.when});

  final InboxEntry entry;
  final String when;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => openNews(context, entry.news),
    child: Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.news.title ?? '',
                  style: AppText.body(15, weight: FontWeight.w700),
                ),
                if (entry.news.body case final body?) ...[
                  const SizedBox(height: 2),
                  Text(body, style: AppText.body(13, color: AppColors.muted)),
                ],
                const SizedBox(height: 6),
                Text(when, style: AppText.body(11, color: AppColors.muted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    ),
  );
}
