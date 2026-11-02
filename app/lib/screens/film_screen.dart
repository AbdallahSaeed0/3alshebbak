import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../services/premiere_live.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/schedule.dart';
import 'cinema_screen.dart';
import '../util/i18n.dart';
import 'go_together_sheet.dart';

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

  /// Premiere's shows, read on the phone (our servers can't reach its site).
  PremiereShows _premiere = PremiereShows.none;
  bool _readingPremiere = false;
  bool _askedPremiere = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_askedPremiere || !PremiereLive.available) return;
    _askedPremiere = true;
    _readingPremiere = true;
    PremiereLive.instance
        .showtimesFor(widget.movie, AppScope.of(context).today)
        .then((shows) {
          if (!mounted) return;
          setState(() {
            _premiere = shows;
            _readingPremiere = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final movie = widget.movie;
    final dates = data.dates(movieId: movie.id, extra: _premiere.showtimes);
    final date = _date != null && dates.contains(_date)
        ? _date!
        : (dates.isEmpty ? null : dates.first);
    final schedule = date == null
        ? const <(Cinema, List<Showtime>)>[]
        : data.movieSchedule(
            movie.id,
            date,
            extra: _premiere.showtimes,
            extraCinemas: _premiere.cinemas,
          );
    final formats = {
      for (final (_, shows) in schedule)
        for (final s in shows) shortFormat(s.format),
    }.toList()..sort();
    final format = formats.contains(_format) ? _format : null;
    final following = data.prefs.isFollowing(movie.id);

    final meta = [
      if (movie.rating != null) '★ ${movie.rating!.toStringAsFixed(1)}',
      if (movie.releaseDate != null) movie.releaseDate!.substring(0, 4),
      if (movie.runtime != null)
        tr('${movie.runtime} د', '${movie.runtime} min'),
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
                      following
                          ? tr(
                              'بتتابعه · هنبلغك بالجديد',
                              'Following · we\'ll tell you what\'s new',
                            )
                          : tr('تابِع الفيلم', 'Follow this film'),
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
                          ? BorderSide(color: AppColors.gold)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (movie.trailerUrl case final trailer?) ...[
                        Expanded(
                          child: _SideButton(
                            icon: Icons.play_circle_outline,
                            label: tr('شوف الإعلان', 'Watch trailer'),
                            onPressed: () => launchUrl(
                              Uri.parse(trailer),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: _SideButton(
                          icon: Icons.groups_outlined,
                          label: tr('نروح سوا؟', 'Shall we go?'),
                          onPressed: () => showGoTogether(context, movie),
                        ),
                      ),
                    ],
                  ),
                  if (movie.overview != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      movie.overview!,
                      style: AppText.body(
                        14,
                        color: AppColors.text.withValues(alpha: 0.85),
                      ).copyWith(height: 1.8),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Divider(color: AppColors.hairline, height: 1),
                  const SizedBox(height: 18),
                  Text(tr('المواعيد', 'Showtimes'), style: AppText.display(24)),
                  if (_readingPremiere) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tr(
                            'بنشوف مواعيد بريمير كمان…',
                            'Checking Premiere\'s times too…',
                          ),
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (date == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  tr(
                    'مفيش حفلات جاية للفيلم ده دلوقتي. تابعه ونبلغك أول ما التذاكر تنزل.',
                    'No upcoming shows for this film right now. Follow it and we\'ll tell you when tickets go on sale.',
                  ),
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
                : DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.raised),
                  ),
          ),
          // Fade into the page so the title below reads cleanly.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.2),
                    AppColors.background.withValues(alpha: 0.6),
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
                tooltip: tr('رجوع', 'Back'),
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
                tooltip: mine
                    ? tr('شيلها من سينماتي', 'Remove from my cinemas')
                    : tr('ضيفها لسينماتي', 'Add to my cinemas'),
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

/// A secondary action under the follow button.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.text,
      side: BorderSide(color: AppColors.perforation),
      minimumSize: const Size.fromHeight(46),
      textStyle: AppText.body(14, weight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
