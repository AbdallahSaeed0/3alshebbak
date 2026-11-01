import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../services/location.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/cinema_map.dart';
import 'cinema_screen.dart';

/// Every cinema we cover, as a list or on a map. The list puts mine (starred)
/// first, then the rest nearest first when we know where the user is, or by
/// city when we don't.
class CinemasScreen extends StatefulWidget {
  const CinemasScreen({super.key});

  @override
  State<CinemasScreen> createState() => _CinemasScreenState();
}

class _CinemasScreenState extends State<CinemasScreen> {
  final _search = TextEditingController();
  bool _map = false;
  bool _locating = false;

  Future<void> _nearMe() async {
    setState(() => _locating = true);
    final problem = await refreshSpot(AppScope.of(context).prefs);
    if (!mounted) return;
    setState(() => _locating = false);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describe(problem), style: AppText.body(13)),
          action:
              problem == LocationProblem.deniedForever ||
                  problem == LocationProblem.serviceOff
              ? SnackBarAction(
                  label: 'الإعدادات',
                  onPressed: () => openFixFor(problem),
                )
              : null,
        ),
      );
    }
  }

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
    final rest = [
      for (final c in cinemas)
        if (!data.prefs.isMine(c.id)) c,
    ];
    final spot = data.prefs.spot;
    final sections = <String, List<Cinema>>{};
    if (spot != null) {
      double d(Cinema c) => data.distanceKm(c) ?? double.infinity;
      sections['الأقرب ليك'] = rest..sort((a, b) => d(a).compareTo(d(b)));
    } else {
      for (final c in rest) {
        (sections[c.city != null ? cityName(c.city!) : 'أماكن تانية'] ??= [])
            .add(c);
      }
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('السينمات', style: AppText.display(32))),
              IconButton(
                tooltip: 'السينمات القريبة مني',
                onPressed: _locating ? null : _nearMe,
                icon: _locating
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        spot != null
                            ? Icons.my_location
                            : Icons.location_searching,
                        color: AppColors.gold,
                      ),
              ),
              _ViewToggle(
                map: _map,
                onChanged: (map) => setState(() => _map = map),
              ),
            ],
          ),
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
              prefixIcon: const Icon(Icons.search, color: AppColors.muted),
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
    );

    return SafeArea(
      bottom: false,
      child: _map
          ? Column(
              children: [
                header,
                Expanded(child: CinemaMap(cinemas: cinemas)),
              ],
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                if (mine.isNotEmpty) ..._section('سينماتي', mine, data),
                for (final e in sections.entries)
                  ..._section(e.key, e.value, data),
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

  /// "Heliopolis · 3.2 كم" — the distance once we know where the user is.
  static String? _place(AppData data, Cinema c) {
    final km = data.distanceKm(c);
    final parts = [if (c.area != null) c.area!, if (km != null) distance(km)];
    return parts.isEmpty ? null : joinPlace(parts);
  }

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
                      if (_place(data, cinema) case final place?)
                        Text(
                          place,
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

/// List ⇄ map, as two lit segments.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.map, required this.onChanged});

  final bool map;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(bool isMap, IconData icon, String label) {
      final on = map == isMap;
      return Semantics(
        selected: on,
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(isMap),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: on ? AppColors.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: on ? AppColors.onGold : AppColors.muted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(false, Icons.view_list_rounded, 'قائمة'),
          segment(true, Icons.map_outlined, 'خريطة'),
        ],
      ),
    );
  }
}
