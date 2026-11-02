import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/app_data.dart';
import '../data/prefs.dart';
import '../data/supabase_repository.dart';
import 'live_shows.dart';
import 'premiere_live.dart';
import 'vox_live.dart';

/// Keeps Premiere's and VOX's times fresh on the phone without the app open:
/// about once an hour, when there's a connection, Android wakes the app in
/// the background to read them for the films its owner follows or opened
/// this week, so a film page shows them at once. Android picks the moment
/// (and may wait longer to save battery); phones only.
class BackgroundRefresh {
  static const _task = 'live-shows';

  /// Most films one wake-up reads; Premiere takes seconds each.
  static const maxFilms = 8;

  static Future<void> schedule() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Workmanager().initialize(_wakeUp);
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(hours: 1),
        initialDelay: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('Background refresh not scheduled: $e');
    }
  }

  /// The films worth reading: followed first, then opened this week.
  @visibleForTesting
  static List<String> films({
    required Iterable<String> following,
    required List<String> recent,
    required bool Function(String) inCatalog,
  }) => {
    ...following,
    ...recent,
  }.where(inCatalog).take(maxFilms).toList();

  static Future<void> run() async {
    final catalog = await SupabaseShowtimesRepository.cached();
    if (catalog == null) return;
    final data = AppData(catalog, await Prefs.load());
    final recent = await (await LiveCache.open())?.recentMovies() ?? const [];
    final ids = films(
      following: data.prefs.following,
      recent: recent,
      inCatalog: catalog.movies.containsKey,
    );
    for (final id in ids) {
      final movie = catalog.movies[id]!;
      final known = {
        for (final s in catalog.showtimes)
          if (s.movieId == id) '${s.cinemaId}|${s.businessDate}',
      };
      await VoxLive.instance.refresh(movie, data.today, known);
      await PremiereLive.instance.refresh(movie, data.today, known);
    }
    debugPrint('Background refresh: ${ids.length} films');
  }
}

@pragma('vm:entry-point')
void _wakeUp() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await BackgroundRefresh.run();
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    }
    // Done either way: a failed read waits for the next hour, not a retry storm.
    return true;
  });
}
