import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../services/hidden_page.dart';
import '../services/follow_film.dart';
import '../services/live_shows.dart';
import '../services/live_source.dart';
import '../services/premiere_live.dart';
import '../services/vox_live.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/cast_section.dart';
import '../widgets/common.dart';
import '../widgets/trailer_popup.dart';
import '../widgets/schedule.dart';
import 'cinema_screen.dart';
import '../util/i18n.dart';
import 'go_together_sheet.dart';

/// Live sources' names for the "checking…" line, Arabic then English.
const _sourceNames = {
  'premiere': ('بريمير', 'Premiere\'s'),
  'vox': ('ڤوكس', 'VOX\'s'),
};

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

/// The "my cinemas" tab's key among chain names.
const _mineTab = '\u0000mine';

class _FilmScreenState extends State<FilmScreen> {
  String? _date;
  String? _format;

  /// Chain tab: null for all, [_mineTab], or a chain name.
  String? _tab;
  bool _tabChosen = false;

  /// Shows read on the phone off sites our servers can't fully read
  /// (Premiere, VOX's days past its opening day), by source.
  final _live = <String, LiveShows>{};
  final _reading = <String>{};
  final _watching = <StreamSubscription<LiveShows>>[];
  bool _asked = false;

  LiveShows get _liveShows =>
      _live.values.fold(LiveShows.none, (all, s) => all.plus(s));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked || !HiddenPage.available) return;
    _asked = true;
    final data = AppScope.of(context);
    final known = {
      for (final s in data.catalog.showtimes)
        if (s.movieId == widget.movie.id) '${s.cinemaId}|${s.businessDate}',
    };
    for (final source in <LiveSource>[
      PremiereLive.instance,
      VoxLive.instance,
    ]) {
      _reading.add(source.id);
      _watching.add(
        source
            .watch(widget.movie, data.today, known: known)
            .listen(
              (shows) => setState(() => _live[source.id] = shows),
              onDone: () {
                if (mounted) setState(() => _reading.remove(source.id));
              },
            ),
      );
    }
  }

  @override
  void dispose() {
    for (final w in _watching) {
      w.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final movie = widget.movie;
    final live = _liveShows;
    final dates = data.dates(movieId: movie.id, extra: live.showtimes);
    final date = _date != null && dates.contains(_date)
        ? _date!
        : (dates.isEmpty ? null : dates.first);
    final schedule = date == null
        ? const <(Cinema, List<Showtime>)>[]
        : data.movieSchedule(
            movie.id,
            date,
            extra: live.showtimes,
            extraCinemas: live.cinemas,
          );
    // Tabs: my cinemas, all, then each chain showing it that day (most
    // cinemas first, single cinemas last).
    final mine = [
      for (final e in schedule)
        if (data.prefs.isMine(e.$1.id)) e,
    ];
    final byChain = <String, int>{};
    for (final (cinema, _) in schedule) {
      byChain[cinema.chain] = (byChain[cinema.chain] ?? 0) + 1;
    }
    final chains = byChain.keys.toList()
      ..sort((a, b) {
        if ((a == 'Independent') != (b == 'Independent')) {
          return a == 'Independent' ? 1 : -1;
        }
        return byChain[b]!.compareTo(byChain[a]!);
      });
    final tabs = [
      if (mine.isNotEmpty) (_mineTab, tr('سينماتي', 'My cinemas'), mine.length),
      (null, tr('الكل', 'All'), schedule.length),
      if (chains.length > 1)
        for (final c in chains) (c, chainName(c), byChain[c]!),
    ];
    // Opens on my cinemas when they show it; a tab gone from this day falls back to all.
    final tab = !_tabChosen && mine.isNotEmpty
        ? _mineTab
        : tabs.any((t) => t.$1 == _tab)
        ? _tab
        : null;
    final shown = [
      for (final e in schedule)
        if (tab == null ||
            (tab == _mineTab ? data.prefs.isMine(e.$1.id) : e.$1.chain == tab))
          e,
    ];

    final formats = {
      for (final (_, shows) in shown)
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
                  FilmFollowAction(
                    prefs: data.prefs,
                    movieId: movie.id,
                    builder: (onPressed, busy) => FilledButton.icon(
                      onPressed: onPressed,
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              following
                                  ? Icons.notifications_active
                                  : Icons.notifications_none,
                              size: 18,
                            ),
                      label: Text(
                        following
                            ? tr('بتتابع الفيلم', 'Following this film')
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
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (movie.trailerKey != null) ...[
                        Expanded(
                          child: _SideButton(
                            icon: Icons.play_circle_outline,
                            label: tr('شوف الإعلان', 'Watch trailer'),
                            onPressed: () => showTrailer(context, movie),
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
                  if (movie.credits case final credits?) ...[
                    const SizedBox(height: 22),
                    CastSection(
                      movie: movie,
                      credits: credits,
                      onFilm: (m) => openFilm(context, m),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Divider(color: AppColors.hairline, height: 1),
                  const SizedBox(height: 18),
                  Text(tr('المواعيد', 'Showtimes'), style: AppText.display(24)),
                  if (_reading.isNotEmpty) ...[
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
                            'بنشوف مواعيد ${_reading.map((s) => _sourceNames[s]!.$1).join(' و')} كمان…',
                            'Checking ${_reading.map((s) => _sourceNames[s]!.$2).join(' and ')} times too…',
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
            if (tabs.length > 1)
              SliverToBoxAdapter(
                child: _ChainTabs(
                  tabs: tabs,
                  selected: tab,
                  onSelect: (t) => setState(() {
                    _tab = t;
                    _tabChosen = true;
                  }),
                ),
              ),
            if (formats.length > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
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
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final (cinema, shows) = shown[i];
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

/// Underlined tabs over the cinema list: my cinemas, all, each chain, with
/// how many cinemas each has that day.
class _ChainTabs extends StatelessWidget {
  const _ChainTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<(String?, String, int)> tabs;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    height: 46,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final (key, label, count) in tabs)
          Semantics(
            selected: key == selected,
            button: true,
            child: InkWell(
              onTap: () => onSelect(key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: key == selected
                          ? AppColors.gold
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppText.body(
                        14,
                        weight: FontWeight.w700,
                        color: key == selected
                            ? AppColors.text
                            : AppColors.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: key == selected
                            ? AppColors.gold
                            : AppColors.raised,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: AppText.body(
                          11,
                          weight: FontWeight.w700,
                          color: key == selected
                              ? AppColors.onGold
                              : AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
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
