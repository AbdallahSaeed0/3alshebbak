import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/schedule.dart';
import 'film_screen.dart';

void openCinema(BuildContext context, Cinema cinema) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => CinemaScreen(cinema: cinema)));

/// One cinema: where it is, add it to my cinemas, and its films per day.
class CinemaScreen extends StatefulWidget {
  const CinemaScreen({super.key, required this.cinema});

  final Cinema cinema;

  @override
  State<CinemaScreen> createState() => _CinemaScreenState();
}

class _CinemaScreenState extends State<CinemaScreen> {
  String? _date;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final cinema = widget.cinema;
    final mine = data.prefs.isMine(cinema.id);
    final dates = data.dates(cinemaId: cinema.id);
    final date = _date != null && dates.contains(_date)
        ? _date!
        : (dates.isEmpty ? null : dates.first);
    final schedule = date == null
        ? const <(Movie, List<Showtime>)>[]
        : data.cinemaSchedule(cinema.id, date);
    final place = [cinema.area, cinema.city].whereType<String>().join(' · ');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    CircleIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    CircleIconButton(
                      icon: mine ? Icons.star : Icons.star_border,
                      color: mine ? AppColors.gold : AppColors.text,
                      tooltip: mine ? 'شيلها من سينماتي' : 'ضيفها لسينماتي',
                      onPressed: () => data.prefs.toggleCinema(cinema.id),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cinema.chain != 'Independent')
                    Text(
                      cinema.chain.toUpperCase(),
                      style: AppText.body(
                        12,
                        color: AppColors.gold,
                        weight: FontWeight.w700,
                      ).copyWith(letterSpacing: 1),
                    ),
                  Text(
                    cinema.nameAr ?? cinema.name,
                    style: AppText.display(32),
                  ),
                  if (cinema.nameAr != null)
                    Text(
                      cinema.name,
                      style: AppText.body(13, color: AppColors.muted),
                    ),
                  if (place.isNotEmpty)
                    Text(
                      place,
                      style: AppText.body(13, color: AppColors.muted),
                    ),
                  if (cinema.url != null) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(cinema.url!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(
                        cinema.attribution != null
                            ? 'صفحتها على ${cinema.attribution}'
                            : 'موقع السينما',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: const BorderSide(color: AppColors.perforation),
                        minimumSize: const Size(0, 44),
                        textStyle: AppText.body(13, weight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          if (date == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'مفيش حفلات جاية في السينما دي دلوقتي',
                  style: AppText.body(14, color: AppColors.muted),
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: DateStrip(
                dates: dates,
                selected: date,
                today: data.today,
                onSelect: (d) => setState(() => _date = d),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              sliver: SliverList.separated(
                itemCount: schedule.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final (movie, shows) = schedule[i];
                  return Panel(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => openFilm(context, movie),
                          child: Poster(
                            movie: movie,
                            width: 64,
                            height: 96,
                            radius: 8,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => openFilm(context, movie),
                                child: Text(
                                  movie.displayTitle,
                                  style: AppText.body(
                                    15,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              FormatRows(showtimes: shows),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          if (cinema.attribution != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Text(
                  'مواعيد السينما دي من ${cinema.attribution}',
                  style: AppText.body(12, color: AppColors.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
