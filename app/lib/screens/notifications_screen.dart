import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/inbox.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/schedule.dart';
import 'news_screen.dart';

void openNotifications(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

/// What this phone's films and cinemas were told in the last two weeks;
/// tapping one shows what it was about, like tapping the notification. Built
/// from the catalog's news, so it works after a reinstall too.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final prefs = data.prefs;
    final entries = inboxFromNews(
      data.catalog,
      everyFilm: prefs.everyFilm,
      following: prefs.following,
      allCinemas: prefs.allCinemaAlerts,
      myCinemas: prefs.myCinemas,
    );
    final cairoNow = data.cairoNow;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('الإشعارات', 'Notifications'),
          style: AppText.display(24),
        ),
        backgroundColor: AppColors.background,
      ),
      body: RefreshIndicator(
        onRefresh: () async => await data.refresh?.call(),
        child: entries.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Text(
                    data.catalog.news.isEmpty
                        ? tr(
                            'لسه مفيش أخبار. اسحب لتحت عشان نحدّث.',
                            'No news yet. Pull down to refresh.',
                          )
                        : tr(
                            'مفيش جديد في آخر أسبوعين للأفلام والسينمات اللي اخترتها. تقدر تتابع أفلام أكتر، أو تشغّل «كل الأفلام» من الإعدادات.',
                            'Nothing new in the last two weeks for your films and cinemas. Follow more films, or turn on "every film" in Settings.',
                          ),
                    textAlign: TextAlign.center,
                    style: AppText.body(15, color: AppColors.muted),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _EntryCard(
                  entry: entries[i],
                  when: _when(entries[i].sentAt, cairoNow),
                ),
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
