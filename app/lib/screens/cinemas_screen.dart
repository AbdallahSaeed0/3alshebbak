import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'cinema_screen.dart';

/// Every cinema we cover: mine (starred) first, then by city. The map view
/// comes once cinemas have coordinates.
class CinemasScreen extends StatefulWidget {
  const CinemasScreen({super.key});

  @override
  State<CinemasScreen> createState() => _CinemasScreenState();
}

class _CinemasScreenState extends State<CinemasScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final cinemas = data.cinemas(query: _search.text);
    final mine = [
      for (final c in cinemas)
        if (data.prefs.isMine(c.id)) c,
    ];
    final byCity = <String, List<Cinema>>{};
    for (final c in cinemas) {
      if (!data.prefs.isMine(c.id))
        (byCity[c.city ?? 'أماكن تانية'] ??= []).add(c);
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('السينمات', style: AppText.display(32)),
                  Text(
                    '${data.catalog.cinemas.length} سينما في مصر · النجمة تضيفها لسينماتك',
                    style: AppText.body(12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: AppText.body(14),
                    decoration: InputDecoration(
                      hintText: 'دوّر على سينما أو منطقة',
                      hintStyle: AppText.body(14, color: AppColors.muted),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.muted,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.hairline),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (mine.isNotEmpty) ..._section('سينماتي', mine, data),
          for (final e in byCity.entries) ..._section(e.key, e.value, data),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<Cinema> cinemas, AppData data) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(
          title,
          style: AppText.display(
            20,
            color: title == 'سينماتي' ? AppColors.gold : AppColors.text,
          ),
        ),
      ),
    ),
    SliverList.builder(
      itemCount: cinemas.length,
      itemBuilder: (context, i) => _CinemaRow(cinema: cinemas[i]),
    ),
  ];
}

class _CinemaRow extends StatelessWidget {
  const _CinemaRow({required this.cinema});
  final Cinema cinema;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final mine = data.prefs.isMine(cinema.id);
    final next = data.nextShow(cinemaId: cinema.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: mine ? const Color(0xFF5C4520) : AppColors.hairline,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openCinema(context, cinema),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cinema.label,
                        style: AppText.body(15, weight: FontWeight.w700),
                      ),
                      if (cinema.area != null)
                        Text(
                          cinema.area!,
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                      if (next != null)
                        Text(
                          'الجاية: ${data.movie(next.movieId).displayTitle} · ${clock(next.wallClock)} ${period(next.wallClock)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(12, color: AppColors.gold),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: mine ? 'شيلها من سينماتي' : 'ضيفها لسينماتي',
                  onPressed: () => data.prefs.toggleCinema(cinema.id),
                  icon: Icon(
                    mine ? Icons.star : Icons.star_border,
                    color: mine ? AppColors.gold : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
