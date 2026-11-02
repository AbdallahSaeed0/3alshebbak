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

/// Browse and search: what's showing this week (or opening later), filtered
/// by experience and by "my cinemas only". A search also lists the cinemas
/// it matches.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

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
                  Text('استكشف', style: AppText.display(32)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: AppText.body(14),
                    decoration: InputDecoration(
                      hintText: 'فيلم أو سينما، عربي أو إنجليزي',
                      hintStyle: AppText.body(14, color: AppColors.muted),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.muted,
                      ),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'امسح',
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.muted,
                              ),
                              onPressed: () => setState(_search.clear),
                            ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.hairline),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('في السينما دلوقتي'),
                      ),
                      ButtonSegment(value: true, label: Text('قريبًا')),
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
                      side: const BorderSide(color: AppColors.hairline),
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
                    avatar: const Icon(
                      Icons.theaters,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    label: Text(
                      cinemas[i].label,
                      style: AppText.body(13, weight: FontWeight.w600),
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.hairline),
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
                allLabel: 'كل الأنواع',
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
                    'سينماتي بس',
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
                    ? '$count فيلم جايين'
                    : '$count فيلم الأسبوع ده${_format != null ? ' · $_format' : ''}',
                style: AppText.body(12, color: AppColors.muted),
              ),
            ),
          ),
          if (count == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'مفيش أفلام بالشكل ده. جرّب تشيل فلتر.',
                  style: AppText.body(14, color: AppColors.muted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
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
                      ? 'في ${cinemaCount(showing[i].cinemaCount)}'
                      : 'من ${dayLabel(upcoming![i].firstDate)}';
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
        ],
      ),
    );
  }
}
