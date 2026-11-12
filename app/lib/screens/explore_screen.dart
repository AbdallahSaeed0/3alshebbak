import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/search.dart';
import '../widgets/common.dart';
import '../widgets/schedule.dart';
import 'cinema_screen.dart';
import 'film_screen.dart';
import '../util/i18n.dart';

/// Browse and search: what's showing this week (or opening later), filtered
/// by experience and by "my cinemas only". A search also lists the cinemas
/// it matches.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, this.searchFocus});

  final FocusNode? searchFocus;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  bool _comingSoon = false;
  bool _mineOnly = false;
  String? _format;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final query = _search.text;
    final q = SearchQuery(query);
    final showing = _comingSoon
        ? null
        : data.nowShowing(query: query, format: _format, mineOnly: _mineOnly);
    final upcoming = _comingSoon
        ? [
            for (final u in data.upcoming(minDaysAhead: 1, maxDaysAhead: 365))
              if (AppData.movieMatches(u.movie, q)) u,
          ]
        : null;
    final cinemas = q.isEmpty ? const <Cinema>[] : data.cinemas(query: query);
    final count = showing?.length ?? upcoming!.length;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('استكشف', 'Explore'), style: AppText.display(32)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    focusNode: widget.searchFocus,
                    textInputAction: TextInputAction.search,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (_) => setState(() {}),
                    style: AppText.body(14),
                    decoration: InputDecoration(
                      hintText: tr(
                        'فيلم أو سينما، عربي أو إنجليزي',
                        'Film or cinema, Arabic or English',
                      ),
                      hintStyle: AppText.body(14, color: AppColors.muted),
                      prefixIcon: Icon(Icons.search, color: AppColors.muted),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: tr('امسح', 'Delete'),
                              icon: Icon(Icons.close, color: AppColors.muted),
                              onPressed: () => setState(_search.clear),
                            ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.hairline),
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(tr('في السينما دلوقتي', 'In cinemas now')),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(tr('قريبًا', 'Coming soon')),
                      ),
                    ],
                    selected: {_comingSoon},
                    onSelectionChanged: (s) =>
                        setState(() => _comingSoon = s.first),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.gold,
                      selectedForegroundColor: AppColors.onGold,
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.muted,
                      side: BorderSide(color: AppColors.hairline),
                      textStyle: AppText.body(14, weight: FontWeight.w700),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (cinemas.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text(
                  cinemaCount(cinemas.length),
                  style: AppText.body(12, color: AppColors.muted),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: cinemas.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ActionChip(
                    avatar: Icon(
                      Icons.theaters,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    label: Text(
                      cinemas[i].label,
                      style: AppText.body(13, weight: FontWeight.w600),
                    ),
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: AppColors.hairline),
                    onPressed: () => openCinema(context, cinemas[i]),
                  ),
                ),
              ),
            ),
          ],
          if (!_comingSoon) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            SliverToBoxAdapter(
              child: FilterPills(
                options: AppData.formatFilters,
                selected: _format,
                allLabel: tr('كل الأنواع', 'All formats'),
                onSelect: (f) => setState(() => _format = f),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SwitchListTile(
                  value: _mineOnly,
                  onChanged: (v) => setState(() => _mineOnly = v),
                  title: Text(
                    tr('سينماتي بس', 'My cinemas only'),
                    style: AppText.body(14, weight: FontWeight.w600),
                  ),
                  activeThumbColor: AppColors.gold,
                  dense: true,
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                _comingSoon
                    ? tr('$count فيلم جايين', '$count films coming')
                    : tr('$count فيلم الأسبوع ده', '$count films this week') +
                          (_format != null ? ' · $_format' : ''),
                style: AppText.body(12, color: AppColors.muted),
              ),
            ),
          ),
          if (count == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  tr(
                    'مفيش أفلام بالشكل ده. جرّب تشيل فلتر.',
                    'No films match. Try removing a filter.',
                  ),
                  style: AppText.body(14, color: AppColors.muted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, barSpace(context)),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.48,
                ),
                itemCount: count,
                itemBuilder: (context, i) {
                  final movie = showing != null
                      ? showing[i].movie
                      : upcoming![i].movie;
                  final sub = showing != null
                      ? tr(
                          'في ${cinemaCount(showing[i].cinemaCount)}',
                          'In ${cinemaCount(showing[i].cinemaCount)}',
                        )
                      : tr(
                          'من ${dayLabel(upcoming![i].firstDate)}',
                          'From ${dayLabel(upcoming[i].firstDate)}',
                        );
                  return InkWell(
                    onTap: () => openFilm(context, movie),
                    borderRadius: BorderRadius.circular(10),
                    child: LayoutBuilder(
                      builder: (context, box) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Poster(
                            movie: movie,
                            width: box.maxWidth,
                            height: box.maxWidth * 1.5,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            movie.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(13, weight: FontWeight.w700),
                          ),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(
                              11,
                              color: _comingSoon
                                  ? AppColors.gold
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const KeyboardSpace(),
        ],
      ),
    );
  }
}
