import 'package:flutter/material.dart';

import '../data/alert_news.dart';
import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/common.dart';
import '../widgets/schedule.dart';
import 'film_screen.dart';

void openNews(BuildContext context, AlertNews news) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => NewsScreen(news: news)));

/// What a tapped notification was about: for each film, the new showtimes
/// by cinema and day, each one tappable like anywhere else in the app.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key, required this.news});

  final AlertNews news;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  Future<List<Showtime>>? _shows;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shows ??= _load();
  }

  Future<List<Showtime>> _load() {
    final data = AppScope.of(context);
    return fetchNews(
      widget.news,
      data.catalog,
      myCinemas: data.prefs.allCinemaAlerts ? {} : data.prefs.myCinemas,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final news = widget.news;
    final films = [
      for (final f in news.films)
        if (data.catalog.movies[f.movieId] case final movie?) (f, movie),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('الجديد', 'What\'s new'), style: AppText.display(24)),
        backgroundColor: AppColors.background,
      ),
      body: FutureBuilder<List<Showtime>>(
        future: _shows,
        builder: (context, snap) {
          final failed = snap.hasError;
          final loading = snap.connectionState != ConnectionState.done;
          final shows = snap.data ?? const <Showtime>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (news.title != null)
                Text(news.title!, style: AppText.display(20)),
              if (news.body != null) ...[
                const SizedBox(height: 4),
                Text(
                  news.body!,
                  style: AppText.body(14, color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 16),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (failed)
                _Notice(
                  tr(
                    'ما قدرناش نجيب تفاصيل الحفلات دلوقتي.',
                    'Couldn\'t load the showtimes right now.',
                  ),
                  action: TextButton(
                    onPressed: () => setState(() => _shows = _load()),
                    child: Text(tr('حاول تاني', 'Try again')),
                  ),
                ),
              if (!loading)
                for (final (film, movie) in films)
                  _FilmNews(
                    film: film,
                    movie: movie,
                    shows: [
                      for (final s in shows)
                        if (s.movieId == movie.id) s,
                    ],
                    showDetails: !failed,
                  ),
              if (!loading && films.isEmpty)
                _Notice(
                  tr(
                    'الأفلام دي مش موجودة في المواعيد دلوقتي.',
                    'These films aren\'t in the schedule any more.',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One film's news: what happened, then its new shows by cinema and day.
class _FilmNews extends StatelessWidget {
  const _FilmNews({
    required this.film,
    required this.movie,
    required this.shows,
    required this.showDetails,
  });

  final NewsFilm film;
  final Movie movie;
  final List<Showtime> shows;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final cinemas = AppScope.of(context).catalog.cinemas;
    // Cinema → day → shows, in the order the shows come (soonest first).
    final grouped = <String, Map<String, List<Showtime>>>{};
    for (final s in shows) {
      ((grouped[s.cinemaId] ??= {})[s.businessDate] ??= []).add(s);
    }
    final kind = switch (film.kind) {
      NewsKind.opened => tr('الحجز فتح', 'Tickets on sale'),
      NewsKind.days => tr('أيام حجز جديدة', 'New days on sale'),
      NewsKind.shows => tr('حفلات جديدة', 'New showtimes'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => openFilm(context, movie),
                  child: Poster(movie: movie, width: 56, height: 84, radius: 8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(movie.displayTitle, style: AppText.display(18)),
                      const SizedBox(height: 2),
                      Text(
                        showDetails && shows.isNotEmpty
                            ? '$kind · ${_count(shows.length)}'
                            : kind,
                        style: AppText.body(
                          13,
                          color: AppColors.gold,
                          weight: FontWeight.w700,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => openFilm(context, movie),
                        child: Text(tr('صفحة الفيلم', 'Film page')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (showDetails && shows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  tr(
                    'الحفلات الجديدة دي عدّت أو اتشالت من الجدول.',
                    'These new shows are over or no longer listed.',
                  ),
                  style: AppText.body(13, color: AppColors.muted),
                ),
              ),
            for (final MapEntry(key: cinemaId, value: days)
                in grouped.entries) ...[
              const SizedBox(height: 12),
              Text(
                cinemas[cinemaId]?.label ?? cinemaId,
                style: AppText.body(15, weight: FontWeight.w700),
              ),
              for (final MapEntry(key: day, value: dayShows)
                  in days.entries) ...[
                const SizedBox(height: 6),
                Text(
                  dayLabel(day),
                  style: AppText.body(13, color: AppColors.muted),
                ),
                FormatRows(showtimes: dayShows),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _count(int n) => Lang.english
      ? '$n ${n == 1 ? 'show' : 'shows'}'
      : switch (n) {
          1 => 'حفلة واحدة',
          2 => 'حفلتين',
          <= 10 => '$n حفلات',
          _ => '$n حفلة',
        };
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Panel(
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: AppText.body(14, color: AppColors.muted)),
          ),
          ?action,
        ],
      ),
    ),
  );
}
