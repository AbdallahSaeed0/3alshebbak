import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/i18n.dart';

/// "Shall we go?": tick a few showtimes of a film and send them to friends in
/// one message, so they pick one.
Future<void> showGoTogether(BuildContext context, Movie movie) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GoTogether(movie: movie),
  );
}

class _GoTogether extends StatefulWidget {
  const _GoTogether({required this.movie});
  final Movie movie;

  @override
  State<_GoTogether> createState() => _GoTogetherState();
}

class _GoTogetherState extends State<_GoTogether> {
  final _picked = <Showtime>{};

  /// The film's shows over the next three days: at my cinemas when it plays
  /// at any of them, otherwise everywhere.
  List<(String, List<(Cinema, Showtime)>)> _days(AppData data) {
    final days = <(String, List<(Cinema, Showtime)>)>[];
    for (final date in data.dates(movieId: widget.movie.id).take(3)) {
      final schedule = data.movieSchedule(widget.movie.id, date);
      days.add((
        date,
        [
          for (final (cinema, shows) in schedule)
            for (final s in shows) (cinema, s),
        ],
      ));
    }
    final anyMine = days.any(
      (d) => d.$2.any((e) => data.prefs.isMine(e.$1.id)),
    );
    return [
      for (final (date, shows) in days)
        (
          date,
          [
            for (final e in shows)
              if (!anyMine || data.prefs.isMine(e.$1.id)) e,
          ],
        ),
    ].where((d) => d.$2.isNotEmpty).toList();
  }

  void _share(AppData data) {
    final picked = _picked.toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final lines = [
      for (final (i, s) in picked.indexed)
        '${i + 1}) ${dayLabel(s.businessDate)} · ${clock(s.wallClock)} ${period(s.wallClock)} · ${data.cinema(s.cinemaId).label}',
    ];
    SharePlus.instance.share(
      ShareParams(
        text: [
          tr(
            'نروح «${widget.movie.displayTitle}» سوا؟ 🎬 اختاروا ميعاد:',
            'Shall we see "${widget.movie.displayTitle}"? 🎬 Pick a time:',
          ),
          ...lines,
          tr('— من عالشباك', '— from 3al Shebbak'),
        ].join('\n'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final days = _days(data);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              tr('نروح سوا؟', 'Shall we go?'),
              style: AppText.display(24),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              tr(
                'علّم على كام ميعاد يناسبوك، وابعتهم لصحابك يختاروا.',
                'Tick a few times that suit you and send them to friends to pick.',
              ),
              style: AppText.body(13, color: AppColors.muted),
            ),
          ),
          Flexible(
            child: days.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr(
                        'مفيش حفلات جاية للفيلم ده.',
                        'No upcoming shows for this film.',
                      ),
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (date, shows) in days) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Text(
                            dayLabel(date),
                            style: AppText.body(
                              13,
                              weight: FontWeight.w700,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                        for (final (cinema, s) in shows)
                          CheckboxListTile(
                            value: _picked.contains(s),
                            onChanged: (on) => setState(
                              () => on == true
                                  ? _picked.add(s)
                                  : _picked.remove(s),
                            ),
                            activeColor: AppColors.gold,
                            checkColor: AppColors.onGold,
                            dense: true,
                            title: Text(
                              '${clock(s.wallClock)} ${period(s.wallClock)} · ${shortFormat(s.format)}',
                              style: AppText.body(14, weight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              cinema.label,
                              style: AppText.body(12, color: AppColors.muted),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton.icon(
              onPressed: _picked.isEmpty ? null : () => _share(data),
              icon: const Icon(Icons.ios_share),
              label: Text(
                _picked.isEmpty
                    ? tr('علّم على ميعاد الأول', 'Tick a time first')
                    : tr(
                        'ابعت ${_picked.length} مواعيد لصحابك',
                        'Send ${_picked.length} times to friends',
                      ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.onGold,
                minimumSize: const Size.fromHeight(50),
                textStyle: AppText.body(15, weight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
