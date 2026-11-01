import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/schedule.dart';
import 'cinema_screen.dart';

void openFilm(BuildContext context, Movie movie) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => FilmScreen(movie: movie)));

/// A movie: what it is, follow it, and where/when it's showing per day.
class FilmScreen extends StatefulWidget {
  const FilmScreen({super.key, required this.movie});

  final Movie movie;

  @override
  State<FilmScreen> createState() => _FilmScreenState();
}

class _FilmScreenState extends State<FilmScreen> {
  String? _date;
  String? _format;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final movie = widget.movie;
    final dates = data.dates(movieId: movie.id);
    final date = _date != null && dates.contains(_date)
        ? _date!
        : (dates.isEmpty ? null : dates.first);
    final schedule = date == null
        ? const <(Cinema, List<Showtime>)>[]
        : data.movieSchedule(movie.id, date);
    final formats = {
      for (final (_, shows) in schedule)
        for (final s in shows) shortFormat(s.format),
    }.toList()..sort();
    final format = formats.contains(_format) ? _format : null;
    final following = data.prefs.isFollowing(movie.id);

    final meta = [
      if (movie.releaseDate != null) movie.releaseDate!.substring(0, 4),
      if (movie.runtime != null) '${movie.runtime} د',
      ...movie.genres.take(2),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Hero(movie: movie)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(movie.displayTitle, style: AppText.display(34)),
                  if (movie.subtitle != null)
                    Text(
                      movie.subtitle!,
                      style: AppText.body(13, color: AppColors.muted),
                    ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final m in meta) _Tag(m)],
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => data.prefs.toggleFollow(movie.id),
                    icon: Icon(
                      following
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                      size: 18,
                    ),
                    label: Text(
                      following ? 'بتتابعه · هنبلغك بالجديد' : 'تابِع الفيلم',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: following
                          ? AppColors.raised
                          : AppColors.gold,
                      foregroundColor: following
                          ? AppColors.gold
                          : AppColors.onGold,
                      minimumSize: const Size.fromHeight(52),
                      textStyle: AppText.body(15, weight: FontWeight.w700),
                      side: following
                          ? const BorderSide(color: AppColors.gold)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  if (movie.overview != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      movie.overview!,
                      style: AppText.body(
                        14,
                        color: const Color(0xFFD9D0C2),
                      ).copyWith(height: 1.8),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Divider(color: AppColors.hairline, height: 1),
                  const SizedBox(height: 18),
                  Text('المواعيد', style: AppText.display(24)),
                ],
              ),
            ),
          ),
          if (date == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'مفيش حفلات جاية للفيلم ده دلوقتي. تابعه ونبلغك أول ما التذاكر تنزل.',
                  style: AppText.body(14, color: AppColors.muted),
                ),
              ),
            )
          else ...[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: DateStrip(
                dates: dates,
                selected: date,
                today: data.today,
                onSelect: (d) => setState(() => _date = d),
              ),
            ),
            if (formats.length > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilterPills(
                    options: formats,
                    selected: format,
                    onSelect: (f) => setState(() => _format = f),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              sliver: SliverList.separated(
                itemCount: schedule.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final (cinema, shows) = schedule[i];
                  final filtered = format == null
                      ? shows
                      : [
                          for (final s in shows)
                            if (shortFormat(s.format) == format) s,
                        ];
                  if (filtered.isEmpty) return const SizedBox.shrink();
                  return _CinemaBlock(cinema: cinema, showtimes: filtered);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.movie});
  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final backdrop = movie.backdropPath != null
        ? 'https://image.tmdb.org/t/p/w780${movie.backdropPath}'
        : null;
    return SizedBox(
      height: 320,
      child: Stack(
        children: [
          Positioned.fill(
            child: backdrop != null
                ? Image.network(
                    backdrop,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  )
                : const DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.raised),
                  ),
          ),
          // Fade into the page so the title below reads cleanly.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x330B0A08),
                    Color(0x990B0A08),
                    AppColors.background,
                  ],
                  stops: [0, 0.6, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CircleIconButton(
                icon: Icons.arrow_back,
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          PositionedDirectional(
            start: 20,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Poster(movie: movie, width: 116, height: 174, radius: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.raised,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.perforation),
    ),
    child: Text(text, style: AppText.body(11, weight: FontWeight.w600)),
  );
}

class _CinemaBlock extends StatelessWidget {
  const _CinemaBlock({required this.cinema, required this.showtimes});

  final Cinema cinema;
  final List<Showtime> showtimes;

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    final mine = prefs.isMine(cinema.id);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => openCinema(context, cinema),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cinema.label,
                          style: AppText.body(15, weight: FontWeight.w700),
                        ),
                        Text(
                          [
                            cinema.area,
                            if (cinema.city != null) cityName(cinema.city!),
                          ].whereType<String>().join(' · '),
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: mine ? 'شيلها من سينماتي' : 'ضيفها لسينماتي',
                onPressed: () => prefs.toggleCinema(cinema.id),
                icon: Icon(
                  mine ? Icons.star : Icons.star_border,
                  color: mine ? AppColors.gold : AppColors.muted,
                ),
              ),
            ],
          ),
          FormatRows(showtimes: showtimes),
        ],
      ),
    );
  }
}
