import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/common.dart';
import 'film_screen.dart';
import 'showtime_sheet.dart';

/// A chat that only takes taps: it asks, you pick a chip, it answers with the
/// showtimes or cinemas from the catalog the app already has. Nothing is
/// typed and nothing leaves the phone, so it's instant and always right.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

/// Where to look: one city, or near the user (their last known spot).
typedef _Where = ({String? city, bool near});

class _Option {
  const _Option(this.label, this.onTap, {this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
}

class _Msg {
  _Msg.bot(this.text) : mine = false, body = null;
  _Msg.me(this.text) : mine = true, body = null;
  _Msg.card(this.body) : mine = false, text = null;

  final bool mine;
  final String? text;
  final Widget? body;
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _log = <_Msg>[];
  var _options = <_Option>[];
  final _scroll = ScrollController();
  bool _started = false;

  AppData get _data => AppScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _say(List<_Msg> msgs, List<_Option> options) {
    setState(() {
      _log.addAll(msgs);
      _options = options;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// The user's pick, echoed as their bubble, then what follows from it.
  _Option _pick(String label, VoidCallback then, {IconData? icon}) =>
      _Option(label, () {
        setState(() => _log.add(_Msg.me(label)));
        then();
      }, icon: icon);

  // ── Start ────────────────────────────────────────────────────────────

  void _start({bool again = false}) {
    _say(
      [
        _Msg.bot(
          again
              ? tr('تحب تعرف إيه تاني؟', 'What else would you like to know?')
              : tr(
                  'أهلاً! 👋 أنا هنا أسهّل عليك. عايز تعرف إيه؟',
                  'Hi! 👋 I\'m here to make it easy. What would you like to know?',
                ),
        ),
      ],
      [
        _pick(
          tr('مواعيد فيلم', 'A film\'s showtimes'),
          () => _askWhere(_askFilm),
          icon: Icons.movie_outlined,
        ),
        _pick(
          tr('السينمات في منطقتي', 'Cinemas near me'),
          () => _askWhere(_showCinemas),
          icon: Icons.place_outlined,
        ),
        _pick(
          tr('إيه اللي هيبدأ قريب؟', 'What\'s starting soon?'),
          () => _askWhere(_startingSoon),
          icon: Icons.schedule,
        ),
      ],
    );
  }

  List<_Option> get _again => [
    _pick(
      tr('من الأول', 'Start over'),
      () => _start(again: true),
      icon: Icons.refresh,
    ),
  ];

  // ── Where ────────────────────────────────────────────────────────────

  void _askWhere(void Function(_Where where) then) {
    final spot = _data.prefs.spot;
    _say(
      [_Msg.bot(tr('في أنهي مدينة؟', 'Which city?'))],
      [
        if (spot != null)
          _pick(
            tr('قريب مني', 'Near me'),
            () => then((city: null, near: true)),
            icon: Icons.my_location,
          ),
        for (final (city, _) in _data.cities.take(8))
          _pick(cityName(city), () => then((city: city, near: false))),
      ],
    );
  }

  /// The cinemas [where] means, nearest first when we know where the user is.
  List<Cinema> _cinemas(_Where where) {
    final spot = _data.prefs.spot;
    if (where.near && spot != null) {
      final near = _data.byDistance(spot);
      final close = near
          .where((c) => (_data.distanceKm(c) ?? 999) <= 15)
          .toList();
      return close.length >= 3 ? close : near.take(5).toList();
    }
    final list = _data.catalog.cinemas.values
        .where((c) => c.city == where.city)
        .toList();
    if (spot != null) {
      list.sort(
        (a, b) =>
            (_data.distanceKm(a) ?? 999).compareTo(_data.distanceKm(b) ?? 999),
      );
    } else {
      list.sort((a, b) => a.label.compareTo(b.label));
    }
    return list;
  }

  String _whereLabel(_Where where) => where.near
      ? tr('القريبة منك', 'near you')
      : tr('في ${cityName(where.city!)}', 'in ${cityName(where.city!)}');

  // ── A film's showtimes ───────────────────────────────────────────────

  void _askFilm(_Where where, {int from = 0}) {
    final ids = _cinemas(where).map((c) => c.id).toSet();
    final counts = <String, int>{};
    final weekEnd = isoDate(
      DateTime.parse(_data.today).add(const Duration(days: 7)),
    );
    for (final s in _data.catalog.showtimes) {
      if (ids.contains(s.cinemaId) &&
          s.startsAt.isAfter(_data.now) &&
          s.businessDate.compareTo(weekEnd) <= 0) {
        counts[s.movieId] = (counts[s.movieId] ?? 0) + 1;
      }
    }
    final films = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    if (films.isEmpty) {
      return _say([
        _Msg.bot(
          tr(
            'مفيش أفلام معروضة ${_whereLabel(where)} الأسبوع ده.',
            'Nothing is showing ${_whereLabel(where)} this week.',
          ),
        ),
      ], _again);
    }
    const page = 10;
    final shown = films.skip(from).take(page).toList();
    _say(
      [
        if (from == 0)
          _Msg.bot(
            tr(
              'فيه ${films.length} فيلم ${_whereLabel(where)}. أنهي فيلم؟',
              '${films.length} films ${_whereLabel(where)}. Which one?',
            ),
          ),
      ],
      [
        for (final id in shown)
          _pick(
            _data.movie(id).displayTitle,
            () => _askDay(where, _data.movie(id)),
          ),
        if (from + page < films.length)
          _pick(
            tr('أفلام تانية', 'More films'),
            () => _askFilm(where, from: from + page),
            icon: Icons.more_horiz,
          ),
      ],
    );
  }

  void _askDay(_Where where, Movie movie) {
    final ids = _cinemas(where).map((c) => c.id).toSet();
    final days = _data
        .dates(movieId: movie.id)
        .where(
          (d) => _data
              .movieSchedule(movie.id, d)
              .any((e) => ids.contains(e.$1.id)),
        )
        .take(6)
        .toList();
    if (days.isEmpty) {
      return _say([
        _Msg.bot(
          tr(
            'مفيش حفلات جاية لـ«${movie.displayTitle}» ${_whereLabel(where)}.',
            'No upcoming shows of "${movie.displayTitle}" ${_whereLabel(where)}.',
          ),
        ),
      ], _again);
    }
    _say(
      [_Msg.bot(tr('أنهي يوم؟', 'Which day?'))],
      [
        for (final d in days)
          _pick(dayLabel(d), () => _filmTimes(where, movie, d)),
      ],
    );
  }

  void _filmTimes(_Where where, Movie movie, String day) {
    final order = {for (final (i, c) in _cinemas(where).indexed) c.id: i};
    final schedule =
        _data
            .movieSchedule(movie.id, day)
            .where((e) => order.containsKey(e.$1.id))
            .toList()
          ..sort((a, b) => order[a.$1.id]!.compareTo(order[b.$1.id]!));
    _say(
      [
        _Msg.bot(
          tr(
            '«${movie.displayTitle}» ${dayLabel(day)}، في ${schedule.length} سينما${_data.prefs.spot != null ? '، الأقرب الأول' : ''}:',
            '"${movie.displayTitle}" on ${dayLabel(day)}, at ${schedule.length} cinemas${_data.prefs.spot != null ? ', nearest first' : ''}:',
          ),
        ),
        _Msg.card(
          Column(
            children: [
              _FilmHeader(
                movie: movie,
                day: day,
                cinemas: schedule.length,
                shows: schedule.fold(0, (n, e) => n + e.$2.length),
              ),
              for (final (cinema, shows) in schedule.take(8))
                _CinemaTimes(cinema: cinema, shows: shows),
            ],
          ),
        ),
      ],
      [
        _pick(
          tr('يوم تاني', 'Another day'),
          () => _askDay(where, movie),
          icon: Icons.calendar_today_outlined,
        ),
        _pick(
          tr('صفحة الفيلم', 'Film page'),
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => FilmScreen(movie: movie)),
          ),
          icon: Icons.open_in_new,
        ),
        _pick(
          tr('فيلم تاني', 'Another film'),
          () => _askFilm(where),
          icon: Icons.movie_outlined,
        ),
        ..._again,
      ],
    );
  }

  // ── Cinemas ──────────────────────────────────────────────────────────

  void _showCinemas(_Where where) {
    final cinemas = _cinemas(where).take(8).toList();
    if (cinemas.isEmpty) {
      return _say([
        _Msg.bot(tr('مش لاقي سينمات هنا.', 'No cinemas here.')),
      ], _again);
    }
    _say(
      [
        _Msg.bot(
          _data.prefs.spot != null
              ? tr(
                  'دي السينمات ${_whereLabel(where)}، الأقرب الأول:',
                  'Cinemas ${_whereLabel(where)}, nearest first:',
                )
              : tr(
                  'دي السينمات ${_whereLabel(where)}:',
                  'Cinemas ${_whereLabel(where)}:',
                ),
        ),
        _Msg.card(
          Column(children: [for (final c in cinemas) _CinemaLine(cinema: c)]),
        ),
        _Msg.bot(
          tr(
            'تحب تشوف بتعرض إيه في واحدة منهم؟',
            'Want to see what one of them is showing?',
          ),
        ),
      ],
      [
        for (final c in cinemas.take(6))
          _pick(c.label, () => _askCinemaDay(where, c)),
        ..._again,
      ],
    );
  }

  void _askCinemaDay(_Where where, Cinema cinema) {
    final days = _data.dates(cinemaId: cinema.id).take(5).toList();
    if (days.isEmpty) {
      return _say([
        _Msg.bot(
          tr(
            'مفيش حفلات جاية في ${cinema.label}.',
            'No upcoming shows at ${cinema.label}.',
          ),
        ),
      ], _again);
    }
    _say(
      [_Msg.bot(tr('أنهي يوم؟', 'Which day?'))],
      [
        for (final d in days)
          _pick(dayLabel(d), () => _cinemaDay(where, cinema, d)),
      ],
    );
  }

  void _cinemaDay(_Where where, Cinema cinema, String day) {
    final schedule = _data.cinemaSchedule(cinema.id, day);
    _say(
      [
        _Msg.bot(
          tr(
            '${cinema.label} ${dayLabel(day)}: ${schedule.length} فيلم',
            '${cinema.label} on ${dayLabel(day)}: ${schedule.length} films',
          ),
        ),
        _Msg.card(
          Column(
            children: [
              for (final (movie, shows) in schedule.take(10))
                _FilmTimes(movie: movie, shows: shows),
            ],
          ),
        ),
      ],
      [
        _pick(
          tr('يوم تاني', 'Another day'),
          () => _askCinemaDay(where, cinema),
          icon: Icons.calendar_today_outlined,
        ),
        _pick(
          tr('سينما تانية', 'Another cinema'),
          () => _showCinemas(where),
          icon: Icons.place_outlined,
        ),
        ..._again,
      ],
    );
  }

  // ── Starting soon ────────────────────────────────────────────────────

  void _startingSoon(_Where where) {
    final ids = _cinemas(where).map((c) => c.id).toSet();
    final until = _data.now.add(const Duration(hours: 3));
    final soon =
        _data.catalog.showtimes
            .where(
              (s) =>
                  ids.contains(s.cinemaId) &&
                  s.startsAt.isAfter(_data.now) &&
                  s.startsAt.isBefore(until),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    if (soon.isEmpty) {
      return _say([
        _Msg.bot(
          tr(
            'مفيش حفلات هتبدأ في الـ3 ساعات الجاية ${_whereLabel(where)}.',
            'Nothing starts in the next 3 hours ${_whereLabel(where)}.',
          ),
        ),
      ], _again);
    }
    _say([
      _Msg.bot(
        tr(
          'اللي هيبدأ في الـ3 ساعات الجاية ${_whereLabel(where)}:',
          'Starting in the next 3 hours ${_whereLabel(where)}:',
        ),
      ),
      _Msg.card(
        Column(children: [for (final s in soon.take(10)) _SoonLine(show: s)]),
      ),
    ], _again);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('اسأل عالشباك', 'Ask 3al Shebbak'),
          style: AppText.display(22),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _log.length,
              itemBuilder: (context, i) => _Bubble(msg: _log[i]),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.hairline)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in _options)
                    ActionChip(
                      avatar: o.icon == null
                          ? null
                          : Icon(o.icon, size: 16, color: AppColors.gold),
                      label: Text(o.label, style: AppText.body(13)),
                      backgroundColor: AppColors.raised,
                      side: BorderSide(color: AppColors.goldEdge),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onPressed: o.onTap,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    if (msg.body != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: msg.body,
      );
    }
    final mine = msg.mine;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.gold : AppColors.surface,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(16),
            topEnd: const Radius.circular(16),
            bottomStart: Radius.circular(mine ? 16 : 4),
            bottomEnd: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.hairline),
        ),
        child: Text(
          msg.text!,
          style: AppText.body(
            14,
            weight: mine ? FontWeight.w700 : FontWeight.w500,
            color: mine ? AppColors.onGold : AppColors.text,
          ),
        ),
      ),
    );
  }
}

/// A box in the chat holding a cinema or film and its tappable times.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.hairline),
    ),
    child: child,
  );
}

class _Times extends StatelessWidget {
  const _Times({required this.shows});
  final List<Showtime> shows;

  @override
  Widget build(BuildContext context) {
    final now = AppScope.of(context).now;
    final sorted = [...shows]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final next = sorted.where((s) => s.startsAt.isAfter(now)).firstOrNull;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in sorted)
          _TimeTile(
            show: s,
            past: !s.startsAt.isAfter(now),
            next: identical(s, next),
          ),
      ],
    );
  }
}

/// One showtime in the chat: the time big, AM/PM and the screen type under
/// it. The next one to start is gold; ones already started are faded.
class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.show, this.past = false, this.next = false});
  final Showtime show;
  final bool past;
  final bool next;

  @override
  Widget build(BuildContext context) {
    final format = shortFormat(show.format);
    return Opacity(
      opacity: past ? 0.4 : 1,
      child: Material(
        color: next ? AppColors.gold : AppColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: next ? AppColors.gold : AppColors.perforation,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showShowtimeSheet(context, show),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        clock(show.wallClock),
                        textDirection: TextDirection.ltr,
                        style: AppText.numerals(
                          22,
                          color: next ? AppColors.onGold : AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        period(show.wallClock),
                        style: AppText.body(
                          11,
                          weight: FontWeight.w700,
                          color: next ? AppColors.onGold : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  if (format.isNotEmpty)
                    Text(
                      format,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        10,
                        weight: FontWeight.w700,
                        color: next
                            ? AppColors.onGold
                            : formatTint(show.format),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top of a film's answer: poster, title, the day, and how much is on.
class _FilmHeader extends StatelessWidget {
  const _FilmHeader({
    required this.movie,
    required this.day,
    required this.cinemas,
    required this.shows,
  });
  final Movie movie;
  final String day;
  final int cinemas;
  final int shows;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.raised,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.goldEdge),
    ),
    child: Row(
      children: [
        Poster(movie: movie, width: 48, height: 72, radius: 6),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movie.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(16, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    dayLabel(day),
                    style: AppText.body(
                      13,
                      weight: FontWeight.w700,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                tr(
                  '$shows ${shows == 1 ? 'حفلة' : 'حفلات'} في $cinemas ${cinemas == 1 ? 'سينما' : 'سينمات'}',
                  '$shows ${shows == 1 ? 'show' : 'shows'} at $cinemas ${cinemas == 1 ? 'cinema' : 'cinemas'}',
                ),
                style: AppText.body(12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CinemaTimes extends StatelessWidget {
  const _CinemaTimes({required this.cinema, required this.shows});
  final Cinema cinema;
  final List<Showtime> shows;

  @override
  Widget build(BuildContext context) {
    final km = AppScope.of(context).distanceKm(cinema);
    final where = [cinema.area, cinema.city].whereType<String>().join('، ');
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.raised,
                  border: Border.all(color: AppColors.goldEdge),
                ),
                child: Icon(
                  Icons.theaters_outlined,
                  size: 18,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cinema.label,
                      style: AppText.body(15, weight: FontWeight.w800),
                    ),
                    if (where.isNotEmpty)
                      Text(
                        where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              if (km != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.goldEdge),
                  ),
                  child: Text(
                    distance(km),
                    style: AppText.body(
                      11,
                      weight: FontWeight.w700,
                      color: AppColors.gold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Perforation(vertical: false),
          const SizedBox(height: 10),
          _Times(shows: shows),
          const SizedBox(height: 6),
          Text(
            tr(
              '${shows.length} ${shows.length == 1 ? 'حفلة' : 'حفلات'} · دوس على الميعاد عشان تحجز',
              '${shows.length} ${shows.length == 1 ? 'show' : 'shows'} · tap a time to book',
            ),
            style: AppText.body(11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _FilmTimes extends StatelessWidget {
  const _FilmTimes({required this.movie, required this.shows});
  final Movie movie;
  final List<Showtime> shows;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Poster(movie: movie, width: 44, height: 66, radius: 6),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movie.displayTitle,
                style: AppText.body(14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              _Times(shows: shows),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CinemaLine extends StatelessWidget {
  const _CinemaLine({required this.cinema});
  final Cinema cinema;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final km = data.distanceKm(cinema);
    final next =
        data.catalog.showtimes
            .where(
              (s) => s.cinemaId == cinema.id && s.startsAt.isAfter(data.now),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final first = next.firstOrNull;
    return _Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cinema.label,
                  style: AppText.body(14, weight: FontWeight.w700),
                ),
                if (first != null)
                  Text(
                    tr(
                      'الجاية: ${data.movie(first.movieId).displayTitle} · ${clock(first.wallClock)} ${period(first.wallClock)}',
                      'Next: ${data.movie(first.movieId).displayTitle} · ${clock(first.wallClock)} ${period(first.wallClock)}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12, color: AppColors.muted),
                  ),
              ],
            ),
          ),
          if (km != null)
            Text(distance(km), style: AppText.body(12, color: AppColors.gold)),
        ],
      ),
    );
  }
}

class _SoonLine extends StatelessWidget {
  const _SoonLine({required this.show});
  final Showtime show;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final movie = data.movie(show.movieId);
    return InkWell(
      onTap: () => showShowtimeSheet(context, show),
      borderRadius: BorderRadius.circular(14),
      child: _Panel(
        child: Row(
          children: [
            Text(
              clock(show.wallClock),
              style: AppText.numerals(26, color: AppColors.gold),
            ),
            const SizedBox(width: 6),
            Text(
              period(show.wallClock),
              style: AppText.body(11, color: AppColors.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(14, weight: FontWeight.w700),
                  ),
                  Text(
                    data.cinema(show.cinemaId).label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
