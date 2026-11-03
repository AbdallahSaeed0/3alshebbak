import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'hidden_page.dart';
import 'live_shows.dart';

/// A cinema site the phone reads for itself (premiere_live.dart,
/// vox_live.dart): what it last read for a film comes at once from the
/// phone's cache, then what it reads now, a day at a time where the site
/// allows.
abstract class LiveSource {
  LiveSource(this.id);

  /// Cache key, e.g. "premiere".
  final String id;

  final _fresh = <String, Future<LiveShows>>{};

  /// `--dart-define=LIVE_CACHE=false` for a test build that always reads
  /// afresh, to see how long a first read takes.
  static const _useCache = bool.fromEnvironment(
    'LIVE_CACHE',
    defaultValue: true,
  );

  /// Starts loading the site so a film page opened later doesn't wait for it.
  void warmUp();

  /// Reads [movie]'s shows from [today]. [known] holds "cinemaId|date" pairs
  /// the server already has for it, which needn't be read again. [partial]
  /// gets what's been read so far, for sources that read in steps.
  @protected
  Future<LiveShows> read(
    Movie movie,
    String today,
    Set<String> known,
    void Function(LiveShows) partial,
  );

  /// Reads [movie] afresh and keeps it on the phone, for the background
  /// refresh (background_refresh.dart). Failures are left for next time.
  Future<void> refresh(Movie movie, String today, Set<String> known) async {
    try {
      final shows = await read(movie, today, known, (_) {});
      await (await LiveCache.open())?.write(id, movie.id, shows);
    } catch (e) {
      debugPrint('$id background refresh of ${movie.title}: $e');
    }
  }

  Stream<LiveShows> watch(
    Movie movie,
    String today, {
    Set<String> known = const {},
  }) {
    final out = StreamController<LiveShows>();
    () async {
      if (!HiddenPage.available) return;
      final cache = _useCache ? await LiveCache.open() : null;
      final cached = await cache?.read(id, movie.id);
      if (cached != null) out.add(cached);

      final started = DateTime.now();
      void partial(LiveShows shows) {
        // Until a fresh read has more, the cached one is the better picture.
        if (!out.isClosed &&
            shows.showtimes.length >= (cached?.showtimes.length ?? 0)) {
          out.add(shows);
        }
      }

      final fresh = await (_fresh[movie.id] ??=
          read(movie, today, known, partial).then(
            (shows) {
              cache?.write(id, movie.id, shows);
              return shows;
            },
            onError: (Object e) {
              debugPrint('$id showtimes for ${movie.title}: $e');
              _fresh.remove(movie.id);
              return cached ?? LiveShows.none;
            },
          ));
      debugPrint(
        '$id: ${fresh.showtimes.length} shows for ${movie.title} in '
        '${DateTime.now().difference(started).inMilliseconds} ms',
      );
      out.add(fresh);
    }().whenComplete(out.close);
    return out.stream;
  }
}
