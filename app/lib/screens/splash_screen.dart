import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/prefs.dart';
import '../data/repository.dart';
import '../data/supabase_repository.dart';
import '../theme.dart';
import '../widgets/credit.dart';
import '../widgets/ticket_mark.dart';
import '../util/i18n.dart';

/// Shows the mark with its stub lights chasing while the catalog loads, then
/// hands the loaded [AppData] on. Stays at least [_minimum] so it never flashes.
/// With a catalog saved from last time it opens on that straight away
/// (`stale: true`) and the app refreshes it behind the scenes.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.repository,
    required this.onReady,
  });

  final ShowtimesRepository repository;
  final void Function(AppData data, {bool stale}) onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _minimum = Duration(milliseconds: 900);

  /// Just long enough to see the mark, when the catalog is already here.
  static const _minimumCached = Duration(milliseconds: 200);

  late final AnimationController _lights = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    // Settings load while the cached catalog is read, not after it.
    final prefs = Prefs.load();
    final cached = await SupabaseShowtimesRepository.cached();
    if (cached != null) {
      final results = await Future.wait([
        prefs,
        Future<void>.delayed(_minimumCached),
      ]);
      if (mounted) {
        widget.onReady(AppData(cached, results[0] as Prefs), stale: true);
      }
      return;
    }
    try {
      final results = await Future.wait([
        widget.repository.load(),
        prefs,
        Future<void>.delayed(_minimum),
      ]);
      if (mounted) {
        widget.onReady(AppData(results[0] as CatalogData, results[1] as Prefs));
      }
    } catch (e, stack) {
      debugPrint('Loading showtimes failed: $e\n$stack');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _lights.dispose();
    super.dispose();
  }

  /// Each light peaks a third of a cycle after the one before it.
  List<double> _glow(double t, int count) => [
    for (var i = 0; i < count; i++)
      (math.sin((t - i / count) * 2 * math.pi) + 1) / 2,
  ];

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.16),
            radius: 0.9,
            colors: [AppColors.raised, AppColors.background],
          ),
        ),
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: _lights,
            builder: (context, _) {
              final t = reduceMotion ? 0.25 : _lights.value;
              return Column(
                children: [
                  const Spacer(flex: 5),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.18),
                          blurRadius: 60,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: TicketMark(size: 168, glow: _glow(t, 3)),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'عالشباك',
                    style: AppText.display(58, color: AppColors.gold),
                  ),
                  Text(
                    '3AL SHEBBAK',
                    style: AppText.numerals(
                      16,
                      color: AppColors.muted,
                    ).copyWith(letterSpacing: 8),
                  ),
                  const Spacer(flex: 6),
                  if (_error == null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final g in _glow(t, 3))
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.gold.withValues(
                                alpha: 0.3 + 0.7 * g,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.gold.withValues(
                                    alpha: 0.6 * g,
                                  ),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(
                        'كل حفلات السينما في مصر… في مكان واحد',
                        'Every cinema showtime in Egypt… in one place',
                      ),
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                  ] else ...[
                    Text(
                      tr(
                        'مقدرناش نحمّل المواعيد',
                        'We couldn\'t load the showtimes',
                      ),
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: Text(tr('جرّب تاني', 'Try again')),
                    ),
                  ],
                  const SizedBox(height: 40),
                  const Credit(),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
