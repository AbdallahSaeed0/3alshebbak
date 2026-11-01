import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the phone was when the user last shared their location.
typedef Spot = ({double lat, double lng});

/// What the user picked, kept on the device: their cinemas, the films they
/// follow, where they are, and whether they've been through onboarding.
/// Screens rebuild when it changes (see AppScope).
class Prefs extends ChangeNotifier {
  Prefs._(
    this._store,
    this._cinemas,
    this._following,
    this._spot,
    this._onboarded,
  );

  /// In-memory only, for tests.
  Prefs.memory({
    Set<String>? cinemas,
    Set<String>? following,
    Spot? spot,
    bool onboarded = true,
  }) : _store = null,
       _cinemas = cinemas ?? {...defaultCinemas},
       _following = following ?? {},
       _spot = spot,
       _onboarded = onboarded;

  static const _cinemasKey = 'my_cinemas';
  static const _followingKey = 'following';
  static const _spotKey = 'spot';
  static const _onboardedKey = 'onboarded';

  /// For someone who skips picking: a handful of popular Cairo cinemas.
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
      return Prefs.memory(onboarded: false);
    }
    final spot = store.getStringList(_spotKey);
    return Prefs._(
      store,
      store.getStringList(_cinemasKey)?.toSet() ?? {...defaultCinemas},
      store.getStringList(_followingKey)?.toSet() ?? {},
      spot != null && spot.length == 2
          ? (lat: double.parse(spot[0]), lng: double.parse(spot[1]))
          : null,
      store.getBool(_onboardedKey) ?? false,
    );
  }

  final SharedPreferences? _store;
  final Set<String> _cinemas;
  final Set<String> _following;
  Spot? _spot;
  bool _onboarded;

  Set<String> get myCinemas => Set.unmodifiable(_cinemas);
  Set<String> get following => Set.unmodifiable(_following);
  Spot? get spot => _spot;
  bool get onboarded => _onboarded;

  bool isMine(String cinemaId) => _cinemas.contains(cinemaId);
  bool isFollowing(String movieId) => _following.contains(movieId);

  void toggleCinema(String cinemaId) {
    if (!_cinemas.remove(cinemaId)) _cinemas.add(cinemaId);
    _store?.setStringList(_cinemasKey, _cinemas.toList());
    notifyListeners();
  }

  void setCinemas(Set<String> cinemaIds) {
    _cinemas
      ..clear()
      ..addAll(cinemaIds);
    _store?.setStringList(_cinemasKey, _cinemas.toList());
    notifyListeners();
  }

  void toggleFollow(String movieId) {
    if (!_following.remove(movieId)) _following.add(movieId);
    _store?.setStringList(_followingKey, _following.toList());
    notifyListeners();
  }

  void setSpot(Spot spot) {
    _spot = spot;
    _store?.setStringList(_spotKey, ['${spot.lat}', '${spot.lng}']);
    notifyListeners();
  }

  void finishOnboarding() {
    _onboarded = true;
    _store?.setBool(_onboardedKey, true);
    notifyListeners();
  }
}
