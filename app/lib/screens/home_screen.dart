import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/ticket_mark.dart';
import 'film_screen.dart';
import 'settings_screen.dart' show showCityPicker;
import 'showtime_sheet.dart';

/// "What's on", most urgent first: starting soon, tickets just opened,
/// everything still showing today, then what's coming.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final soon = data.startingSoon();
    final opened = data.upcoming(minDaysAhead: 1, maxDaysAhead: 7);
    final today = data.showingToday();
    final coming = data.upcoming(minDaysAhead: 8, maxDaysAhead: 365);
    final city = data.prefs.homeCity;
    final where = city == null ? 'سينماتك' : 'سينمات ${cityName(city)}';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Header(onSearch: onSearch)),
        _gap(24),
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'قرّب يبدأ',
            leading: const _Dot(color: AppColors.amber),
            subtitle:
                'حفلات في $where خلال ٣ ساعات · الساعة دلوقتي ${clock(data.cairoNow)} ${period(data.cairoNow)}',
          ),
        ),
        _gap(8),
        SliverToBoxAdapter(
          child: soon.isEmpty
              ? _Empty('مفيش حفلات في $where خلال الـ٣ ساعات الجاية')
              : SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    itemCount: soon.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) =>
                        _SoonCard(showtime: soon[i], now: data.now),
                  ),
                ),
        ),
        if (opened.isNotEmpty) ...[
          _gap(24),
          const SliverToBoxAdapter(
            child: SectionHeader(
              title: 'التذاكر نزلت!',
              color: AppColors.gold,
              leading: MarqueeBulbs(),
              subtitle: 'الحجز لسه فاتح · اسبق الزحمة',
            ),
          ),
          _gap(12),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 300,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: opened.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _OpenedCard(item: opened[i]),
              ),
            ),
          ),
        ],
        _gap(28),
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'النهارده في السينما',
            subtitle:
                '${dayLabel(data.today)} · في $where الـ${data.homeCinemaCount}',
          ),
        ),
        _gap(12),
        if (today.isEmpty)
          SliverToBoxAdapter(child: _Empty('خلصت حفلات النهارده في $where'))
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: today.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _TodayCard(day: today[i]),
            ),
          ),
        if (coming.isNotEmpty) ...[
          _gap(28),
          const SliverToBoxAdapter(
            child: SectionHeader(
              title: 'قريبًا',
              subtitle: 'تابِع الفيلم ونقولك أول ما التذاكر تنزل',
            ),
          ),
          _gap(12),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 300,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: coming.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _ComingCard(item: coming[i]),
              ),
            ),
          ),
        ],
        _gap(32),
      ],
    );
  }

  static Widget _gap(double h) =>
      SliverToBoxAdapter(child: SizedBox(height: h));
}

class _Header extends StatelessWidget {
  const _Header({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          children: [
            Row(
              children: [
                const TicketMark(size: 48),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'عالشباك',
                      style: AppText.display(28, color: AppColors.gold),
                    ),
                    Text(
                      '3AL SHEBBAK',
                      style: AppText.numerals(
                        12,
                        color: AppColors.muted,
                      ).copyWith(letterSpacing: 2),
                    ),
                  ],
                ),
                const Spacer(),
                _PillButton(
                  onPressed: () => showCityPicker(context),
                  tooltip: 'السينمات اللي تظهر هنا',
                  child: Row(
                    children: [
                      Text(switch (AppScope.of(context).prefs.homeCity) {
                        null => 'سينماتي',
                        final city => cityName(city),
                      }, style: AppText.body(13, weight: FontWeight.w600)),
                      const Icon(
                        Icons.expand_more,
                        size: 16,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.hairline),
              ),
              child: InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.search,
                        size: 18,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'دوّر على فيلم أو سينما',
                        style: AppText.body(14, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.onPressed,
    required this.child,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.surface,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.hairline)),
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [BoxShadow(color: color, blurRadius: 10)],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Text(message, style: AppText.body(13, color: AppColors.muted)),
  );
}

/// A ticket: movie and cinema on the right, tear line, big start time on the left.
class _SoonCard extends StatelessWidget {
  const _SoonCard({required this.showtime, required this.now});

  final Showtime showtime;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final movie = data.movie(showtime.movieId);
    final cinema = data.cinema(showtime.cinemaId);
    return SizedBox(
      width: 304,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.hairline),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => showShowtimeSheet(context, showtime),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Poster(
                            movie: movie,
                            width: 56,
                            height: 84,
                            radius: 8,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  movie.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body(
                                    16,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  cinema.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body(
                                    12,
                                    color: AppColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _FormatTag(showtime.format),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 108, child: Perforation()),
                  SizedBox(
                    width: 88,
                    // Scales down rather than overflowing with large system text.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          children: [
                            Text(
                              clock(showtime.wallClock),
                              textDirection: TextDirection.ltr,
                              style: AppText.numerals(34),
                            ),
                            Text(
                              period(showtime.wallClock) == 'م'
                                  ? 'مساءً'
                                  : 'صباحًا',
                              style: AppText.body(12, color: AppColors.muted),
                            ),
                            Text(
                              startsIn(showtime.startsAt.difference(now)),
                              maxLines: 1,
                              style: AppText.body(
                                11,
                                color: AppColors.amber,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Notches where the tear line meets the edges (time block is 88 wide, on the left).
          const PositionedDirectional(end: 81, top: -9, child: Notch()),
          const PositionedDirectional(end: 81, bottom: -9, child: Notch()),
        ],
      ),
    );
  }
}

class _FormatTag extends StatelessWidget {
  const _FormatTag(this.format);
  final String format;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF5C4520)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      shortFormat(format),
      style: AppText.body(
        11,
        color: formatTint(format),
        weight: FontWeight.w600,
      ),
    ),
  );
}

String _chains(List<Cinema> cinemas) {
  final chains = cinemas
      .map((c) => c.chain == 'Independent' ? c.name : c.chain)
      .toSet()
      .toList();
  return chains.length <= 2
      ? chains.join(' · ')
      : '${chains.take(2).join(' · ')} +${chains.length - 2}';
}

/// Poster with a "new" badge, tear line, then title, chains and opening day.
class _OpenedCard extends StatelessWidget {
  const _OpenedCard({required this.item});
  final Upcoming item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openFilm(context, item.movie),
      child: SizedBox(
        width: 150,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      Poster(
                        movie: item.movie,
                        width: 148,
                        height: 204,
                        radius: 13,
                      ),
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'جديد',
                            style: AppText.body(
                              11,
                              color: AppColors.onGold,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 2,
                    child: Perforation(vertical: false),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.movie.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(14, weight: FontWeight.w700),
                        ),
                        Text(
                          _chains(item.cinemas),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                        Text(
                          'من ${dayLabel(item.firstDate)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            12,
                            color: AppColors.gold,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(top: 198, left: -9, child: Notch()),
            const Positioned(top: 198, right: -9, child: Notch()),
          ],
        ),
      ),
    );
  }
}

/// One movie: poster, title, how many of my cinemas, and its next showtimes.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.day});
  final MovieDay day;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final movie = day.movie;
    final more = day.showtimes.length - _shown;
    final meta = [
      if (movie.subtitle != null) movie.subtitle!,
      if (movie.runtime != null) '${movie.runtime} د',
      if (movie.genres.isNotEmpty) movie.genres.first,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => openFilm(context, movie),
            child: Poster(movie: movie, width: 88, height: 132),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => openFilm(context, movie),
                  child: Text(
                    movie.displayTitle,
                    style: AppText.body(17, weight: FontWeight.w700),
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(meta, style: AppText.body(12, color: AppColors.muted)),
                Text(
                  'في ${cinemaCount(day.cinemaCount)}',
                  style: AppText.body(12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in day.showtimes.take(_shown))
                      TimeChip(
                        showtime: s,
                        onTap: () => showShowtimeSheet(context, s),
                      ),
                    if (more > 0)
                      // No `alignment`: inside a Wrap that would stretch it to the full row.
                      Container(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.perforation),
                        ),
                        child: Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: Text(
                            '+$more',
                            style: AppText.body(
                              12,
                              color: AppColors.muted,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingCard extends StatelessWidget {
  const _ComingCard({required this.item});
  final Upcoming item;

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    final following = prefs.isFollowing(item.movie.id);
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => openFilm(context, item.movie),
            child: Poster(
              movie: item.movie,
              width: 132,
              height: 192,
              radius: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.movie.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(14, weight: FontWeight.w700),
          ),
          Text(
            dayLabel(item.firstDate),
            style: AppText.body(12, color: AppColors.gold),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () => prefs.toggleFollow(item.movie.id),
              icon: Icon(
                following
                    ? Icons.notifications_active
                    : Icons.notifications_none,
                size: 16,
              ),
              label: Text(
                following ? 'بتتابعه' : 'تابِع',
                style: AppText.body(
                  13,
                  weight: FontWeight.w700,
                  color: AppColors.gold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.gold,
                side: const BorderSide(color: AppColors.gold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
