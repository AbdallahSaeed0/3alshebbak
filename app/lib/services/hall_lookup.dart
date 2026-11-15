import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/halls.dart';
import '../data/models.dart';
import 'hidden_page.dart';
import 'vox_live.dart';

/// Finds the hall of a VOX or Scene show when someone asks for its seat view.
///
/// Their shows say only "Standard" (or "Premiere"…), and a cinema has many such
/// halls. The hall is named only on the show's booking page, which the server
/// mustn't read for every show (VOX's robots.txt keeps bots off booking pages;
/// each Scene booking page opens an order). So the phone reads that one page
/// when its user taps, as their own browser would.
class HallLookup {
  HallLookup._();
  static final instance = HallLookup._();

  static const _headers = {
    'User-Agent':
        '3alShebbak/0.1 (Android app; +https://github.com/AbdallahSaeed0/3alshebbak)',
    'Accept-Language': 'en',
  };

  final _client = http.Client();
  final _found = <String, Future<Hall?>>{};

  /// Whether [s]'s hall can be looked up: a VOX or Scene show with no hall
  /// known yet, at a cinema whose halls are recorded with their ids.
  bool canLookUp(Showtime s) {
    final halls = Halls.instance;
    if (!HiddenPage.available || halls == null) return false;
    if (halls.forShowtime(s) != null) return false;
    final kind = _kind(s);
    return kind != null && halls.hasLookupIds(s.cinemaId, kind);
  }

  static String? _kind(Showtime s) {
    if (s.cinemaId.startsWith('scene:')) {
      return _sceneShow.hasMatch(s.bookingUrl ?? '') ? 'scene' : null;
    }
    return voxCinemaIds.contains(s.cinemaId) ? 'vox' : null;
  }

  static final _sceneShow = RegExp(r'^(https://[^/]+)/showtime-([0-9a-f]+)');

  /// [s]'s hall, or null when it couldn't be found (or isn't recorded).
  Future<Hall?> hallOf(Showtime s, Movie movie) {
    final key = '${s.cinemaId}|${s.startsAt.toIso8601String()}|${s.format}';
    return _found[key] ??= _look(s, movie)
        .catchError((Object e) {
          debugPrint('hall lookup: $e');
          return null;
        })
        .then((hall) {
          if (hall == null) _found.remove(key); // try again next time
          return hall;
        });
  }

  Future<Hall?> _look(Showtime s, Movie movie) async {
    final halls = Halls.instance!;
    switch (_kind(s)) {
      case 'scene':
        final m = _sceneShow.firstMatch(s.bookingUrl!)!;
        final res = await _client
            .get(
              Uri.parse('${m.group(1)}/booking-${m.group(2)}'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 15));
        final hall = RegExp(
          r'var hall_id =\s*"([0-9a-f]+)"',
        ).firstMatch(res.body)?.group(1);
        return hall == null ? null : halls.byId(s.cinemaId, 'scene:$hall');
      case 'vox':
        final vox = VoxLive.instance;
        final session = await vox
            .sessionOf(s, movie)
            .timeout(const Duration(seconds: 20));
        if (session == null) return null;
        final screen = await vox
            .screenOf(session)
            .timeout(const Duration(seconds: 30));
        return screen == null
            ? null
            : halls.byId(s.cinemaId, 'vox:${screen.toUpperCase()}');
    }
    return null;
  }
}
