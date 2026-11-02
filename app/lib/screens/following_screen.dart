import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/ticket_mark.dart';
import 'film_screen.dart';
import '../util/i18n.dart';

/// Films I follow and where each one stands. Push notifications (tickets
/// opened, new showtimes) arrive once the backend sends them.
class FollowingScreen extends StatelessWidget {
  const FollowingScreen({super.key, required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final ids = data.prefs.following
        .where(data.catalog.movies.containsKey)
        .toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                tr('متابعاتي', 'Following'),
                style: AppText.display(32),
              ),
            ),
          ),
          if (ids.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Opacity(
                      opacity: 0.5,
                      child: TicketMark(size: 120, glow: [0, 0, 0]),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(
                        'لسه مش بتتابع أي فيلم',
                        'You\'re not following any films yet',
                      ),
                      style: AppText.display(22),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        'تابِع فيلم ونقولك أول ما التذاكر تنزل أو تنزل حفلات جديدة.',
                        'Follow a film and we\'ll tell you when tickets go on sale or new shows are added.',
                      ),
                      textAlign: TextAlign.center,
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onExplore,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.onGold,
                        minimumSize: const Size(160, 48),
                        textStyle: AppText.body(14, weight: FontWeight.w700),
                      ),
                      child: Text(tr('استكشف الأفلام', 'Explore films')),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.separated(
                itemCount: ids.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final movie = data.movie(ids[i]);
                  final next = data.nextShow(movieId: movie.id);
                  final (status, color) = next == null
                      ? (
                          tr('مستنيين التذاكر تنزل', 'Waiting for tickets'),
                          AppColors.gold,
                        )
                      : next.businessDate == data.today
                      ? (
                          tr('بيتعرض النهارده', 'Showing today'),
                          AppColors.fourDx,
                        )
                      : (
                          tr(
                            'التذاكر نزلت · من ${dayLabel(next.businessDate)}',
                            'Tickets out · from ${dayLabel(next.businessDate)}',
                          ),
                          AppColors.fourDx,
                        );
                  return TapCard(
                    radius: 14,

                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => openFilm(context, movie),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Poster(
                              movie: movie,
                              width: 50,
                              height: 75,
                              radius: 7,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    movie.displayTitle,
                                    style: AppText.body(
                                      15,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: color,
                                          boxShadow: [
                                            BoxShadow(
                                              color: color,
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          status,
                                          style: AppText.body(
                                            12,
                                            color: color,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: tr('بطّل تتابع', 'Unfollow'),
                              onPressed: () =>
                                  data.prefs.toggleFollow(movie.id),
                              icon: Icon(
                                Icons.notifications_off_outlined,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
