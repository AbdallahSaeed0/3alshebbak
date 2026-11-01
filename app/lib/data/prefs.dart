import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user picked, kept on the device: their cinemas and the films they
/// follow. Screens rebuild when it changes (see AppScope).
class Prefs extends ChangeNotifier {
  Prefs._(this._store, this._cinemas, this._following);

  /// In-memory only, for tests.
  Prefs.memory({Set<String>? cinemas, Set<String>? following})
    : _store = null,
      _cinemas = cinemas ?? {...defaultCinemas},
      _following = following ?? {};

  static const _cinemasKey = 'my_cinemas';
  static const _followingKey = 'following';

  /// Until onboarding lets people pick, a handful of popular Cairo cinemas.
  static const defaultCinemas = {
    'elcinema:city-centre-almaza',
    'elcinema:mall-of-egypt',
    'premiere:premiere-point90',
    'scene:cfc',
    'renaissance:downtown',
  };

  /// Falls back to in-memory picks when device storage isn't available, so a
  /// storage problem never keeps the app from opening.
  static Future<Prefs> load() async {
    final SharedPreferences store;
    try {
      store = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('Preferences unavailable, keeping picks in memory: $e');
      return Prefs.memory();
    }
    return Prefs._(
      store,
      store.getStringList(_cinemasKey)?.toSet() ?? {...defaultCinemas},
      store.getStringList(_followingKey)?.toSet() ?? {},
    );
  }

  final SharedPreferences? _store;
  final Set<String> _cinemas;
  final Set<String> _following;

  Set<String> get myCinemas => Set.unmodifiable(_cinemas);
  Set<String> get following => Set.unmodifiable(_following);

  bool isMine(String cinemaId) => _cinemas.contains(cinemaId);
  bool isFollowing(String movieId) => _following.contains(movieId);

  void toggleCinema(String cinemaId) {
    if (!_cinemas.remove(cinemaId)) _cinemas.add(cinemaId);
    _store?.setStringList(_cinemasKey, _cinemas.toList());
    notifyListeners();
  }

  void toggleFollow(String movieId) {
    if (!_following.remove(movieId)) _following.add(movieId);
    _store?.setStringList(_followingKey, _following.toList());
    notifyListeners();
  }
}
