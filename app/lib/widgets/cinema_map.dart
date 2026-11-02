import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../data/prefs.dart';
import '../screens/cinema_screen.dart';
import '../theme.dart';
import 'common.dart';
import '../util/format.dart';
import '../util/i18n.dart';

/// Every cinema as a pin on a Stadia Maps base map, light or dark with the
/// app, credited in the corner. Gold pins are my cinemas; tapping a pin
/// shows its next show and opens it.
class CinemaMap extends StatefulWidget {
  const CinemaMap({super.key, required this.cinemas});

  final List<Cinema> cinemas;

  @override
  State<CinemaMap> createState() => _CinemaMapState();
}

class _CinemaMapState extends State<CinemaMap> {
  final _map = MapController();
  Cinema? _selected;

  /// Stadia Maps' key, given at build time (--dart-define-from-file=
  /// dart_defines.json, kept out of git). Without one the map falls back to
  /// OpenStreetMap's own tiles, darkened, which are for light use only.
  static const _stadiaKey = String.fromEnvironment('STADIA_API_KEY');

  /// Alidade Smooth: quiet streets that leave the pins the loudest thing on
  /// the map, with a native dark version.
  String get _tiles => _stadiaKey.isEmpty
      ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
      : 'https://tiles.stadiamaps.com/tiles/'
            '${AppColors.isDark ? 'alidade_smooth_dark' : 'alidade_smooth'}'
            '/{z}/{x}/{y}{r}.png?api_key=$_stadiaKey';

  /// Cairo, when we don't know where the user is.
  static const _cairo = LatLng(30.0444, 31.2357);

  /// Where the map last centred on the user; a new fix re-centres it.
  Spot? _centredOn;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final spot = data.prefs.spot;
    if (spot != null && spot != _centredOn) {
      // The first time, initialCenter already does it.
      if (_centredOn != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _map.move(LatLng(spot.lat, spot.lng), 12),
        );
      }
      _centredOn = spot;
    }
    final pinned = widget.cinemas.where((c) => c.hasLocation).toList()
      // Mine drawn last, so they sit on top where pins overlap.
      ..sort(
        (a, b) => (data.prefs.isMine(a.id) ? 1 : 0).compareTo(
          data.prefs.isMine(b.id) ? 1 : 0,
        ),
      );

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: spot != null ? LatLng(spot.lat, spot.lng) : _cairo,
            initialZoom: spot != null ? 12 : 10.5,
            minZoom: 5,
            maxZoom: 18,
            backgroundColor: AppColors.background,
            onTap: (_, _) => setState(() => _selected = null),
          ),
          children: [
            TileLayer(
              // A new layer per style, so switching light/dark refetches.
              key: ValueKey(_tiles),
              urlTemplate: _tiles,
              retinaMode:
                  _stadiaKey.isNotEmpty && RetinaMode.isHighDensity(context),
              userAgentPackageName: 'com.shebbak.shebbak',
              tileBuilder: _stadiaKey.isEmpty && AppColors.isDark
                  ? darkModeTileBuilder
                  : null,
            ),
            MarkerLayer(
              markers: [
                if (spot != null)
                  Marker(
                    point: LatLng(spot.lat, spot.lng),
                    width: 22,
                    height: 22,
                    child: const _YouAreHere(),
                  ),
                for (final c in pinned)
                  Marker(
                    point: LatLng(c.lat!, c.lng!),
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: _Pin(
                      mine: data.prefs.isMine(c.id),
                      selected: _selected?.id == c.id,
                      label: c.label,
                      onTap: () => setState(() => _selected = c),
                    ),
                  ),
              ],
            ),
            SimpleAttributionWidget(
              source: Text(
                _stadiaKey.isEmpty
                    ? '© OpenStreetMap contributors'
                    : '© Stadia Maps © OpenMapTiles © OpenStreetMap',
                textDirection: TextDirection.ltr,
              ),
              backgroundColor: AppColors.glass,
            ),
          ],
        ),
        if (_selected case final c?)
          Positioned(
            left: 16,
            right: 16,
            // Clear of the attribution line and the glass tab bar.
            bottom: barSpace(context) + 14,
            child: _PinCard(cinema: c),
          ),
      ],
    );
  }
}

class _YouAreHere extends StatelessWidget {
  const _YouAreHere();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('مكانك', 'You'),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.imax,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: AppColors.imax.withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({
    required this.mine,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool mine;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = mine ? AppColors.gold : AppColors.amber;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.25 : 1,
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.bottomCenter,
          child: Icon(
            Icons.location_on,
            size: 44,
            color: color,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.6), blurRadius: 10),
              const Shadow(color: Colors.black, blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({required this.cinema});
  final Cinema cinema;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final mine = data.prefs.isMine(cinema.id);
    final next = data.nextShow(cinemaId: cinema.id);
    final km = data.distanceKm(cinema);
    final place = joinPlace([
      if (cinema.area != null) cinema.area!,
      if (cinema.city != null) cityName(cinema.city!),
      if (km != null) distance(km),
    ]);
    return TapCard(
      radius: 16,
      mine: mine,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openCinema(context, cinema),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cinema.label,
                      style: AppText.body(16, weight: FontWeight.w700),
                    ),
                    if (place.isNotEmpty)
                      Text(
                        place,
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                    if (next != null)
                      Text(
                        tr(
                          'الجاية: ${data.movie(next.movieId).displayTitle} · ${clock(next.wallClock)} ${period(next.wallClock)}',
                          'Next: ${data.movie(next.movieId).displayTitle} · ${clock(next.wallClock)} ${period(next.wallClock)}',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(12, color: AppColors.gold),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: mine
                    ? tr('شيلها من سينماتي', 'Remove from my cinemas')
                    : tr('ضيفها لسينماتي', 'Add to my cinemas'),
                onPressed: () => data.prefs.toggleCinema(cinema.id),
                icon: Icon(
                  mine ? Icons.star : Icons.star_border,
                  color: mine ? AppColors.gold : AppColors.muted,
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
