import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the phone was when the user last shared their location.
typedef Spot = ({double lat, double lng});

/// Light, dark, or whatever the phone is set to.
enum Appearance { system, light, dark }

/// What the user picked, kept on the device: their cinemas, the films they
/// follow, where they are, which city Home shows, and whether they've been
/// through onboarding.
/// Screens rebuild when it changes (see AppScope).
class Prefs extends ChangeNotifier {
  Prefs._(
    this._store,
    this._cinemas,
    this._following,
    this._spot,
    this._onboarded,
    this._homeCity,
    this._appearance,
    this._english,
    this._everyFilm,
    this._allCinemaAlerts,
  );

  /// In-memory only, for tests.
  Prefs.memory({
    Set<String>? cinemas,
    Set<String>? following,
    Spot? spot,
    bool onboarded = true,
    String? homeCity,
    Appearance appearance = Appearance.system,
    bool english = false,
    bool everyFilm = false,
    bool allCinemaAlerts = false,
  }) : _store = null,
       _cinemas = cinemas ?? {...defaultCinemas},
       _following = following ?? {},
       _spot = spot,
       _onboarded = onboarded,
       _homeCity = homeCity,
       _appearance = appearance,
       _english = english,
       _everyFilm = everyFilm,
       _allCinemaAlerts = allCinemaAlerts;

  static const _cinemasKey = 'my_cinemas';
  static const _followingKey = 'following';
  static const _spotKey = 'spot';
  static const _onboardedKey = 'onboarded';
  static const _homeCityKey = 'home_city';
  static const _appearanceKey = 'appearance';
  static const _englishKey = 'english';
  static const _everyFilmKey = 'alerts_every_film';
  static const _allCinemaAlertsKey = 'alerts_all_cinemas';

  /// For someone who skips picking: a handful of popular Cairo cinemas.
  static const defaultCinemas = {
    'elcinema:city-centre-almaza',
    'elcinema:mall-of-egypt',
    'elcinema:premiere-point90',
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
      store.getString(_homeCityKey),
      Appearance.values.asNameMap()[store.getString(_appearanceKey)] ??
          Appearance.system,
      store.getBool(_englishKey) ?? false,
      store.getBool(_everyFilmKey) ?? false,
      store.getBool(_allCinemaAlertsKey) ?? false,
    );
  }

  final SharedPreferences? _store;
  final Set<String> _cinemas;
  final Set<String> _following;
  Spot? _spot;
  bool _onboarded;
  String? _homeCity;
  Appearance _appearance;
  bool _english;
  bool _everyFilm;
  bool _allCinemaAlerts;

  Set<String> get myCinemas => Set.unmodifiable(_cinemas);
  Set<String> get following => Set.unmodifiable(_following);
  Spot? get spot => _spot;
  bool get onboarded => _onboarded;

  /// Alerts for every film's new showtimes at my cinemas, followed or not.
  bool get everyFilm => _everyFilm;

  void setEveryFilm(bool on) {
    _everyFilm = on;
    _store?.setBool(_everyFilmKey, on);
    notifyListeners();
  }

  /// Alerts from every cinema in Egypt, not only my starred ones.
  bool get allCinemaAlerts => _allCinemaAlerts;

  void setAllCinemaAlerts(bool on) {
    _allCinemaAlerts = on;
    _store?.setBool(_allCinemaAlertsKey, on);
    notifyListeners();
  }

  /// Home shows every cinema in this city; null shows my cinemas.
  String? get homeCity => _homeCity;

  Appearance get appearance => _appearance;

  /// The app in English instead of Arabic.
  bool get english => _english;

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

  void clearSpot() {
    _spot = null;
    _store?.remove(_spotKey);
    notifyListeners();
  }

  void setHomeCity(String? city) {
    _homeCity = city;
    if (city == null) {
      _store?.remove(_homeCityKey);
    } else {
      _store?.setString(_homeCityKey, city);
    }
    notifyListeners();
  }

  void setAppearance(Appearance a) {
    _appearance = a;
    _store?.setString(_appearanceKey, a.name);
    notifyListeners();
  }

  void setEnglish(bool english) {
    _english = english;
    _store?.setBool(_englishKey, english);
    notifyListeners();
  }

  /// What the settings backup keeps (services/settings_backup.dart). Never
  /// the phone's location.
  Map<String, Object?> toBackup() => {
    'v': 1,
    'cinemas': _cinemas.toList()..sort(),
    'following': _following.toList()..sort(),
    'everyFilm': _everyFilm,
    'allCinemaAlerts': _allCinemaAlerts,
    'homeCity': _homeCity,
    'appearance': _appearance.name,
    'english': _english,
  };

  /// Puts a backup's settings back after a reinstall, as if never gone:
  /// onboarding counts as done.
  void restore(Map<String, dynamic> b) {
    List<String> list(Object? v) => v is List ? v.cast<String>() : const [];
    _cinemas
      ..clear()
      ..addAll(list(b['cinemas']));
    _following
      ..clear()
      ..addAll(list(b['following']));
    _everyFilm = b['everyFilm'] == true;
    _allCinemaAlerts = b['allCinemaAlerts'] == true;
    _homeCity = b['homeCity'] as String?;
    _appearance =
        Appearance.values.asNameMap()[b['appearance']] ?? Appearance.system;
    _english = b['english'] == true;
    _onboarded = true;
    final s = _store;
    if (s != null) {
      s.setStringList(_cinemasKey, _cinemas.toList());
      s.setStringList(_followingKey, _following.toList());
      s.setBool(_everyFilmKey, _everyFilm);
      s.setBool(_allCinemaAlertsKey, _allCinemaAlerts);
      _homeCity == null
          ? s.remove(_homeCityKey)
          : s.setString(_homeCityKey, _homeCity!);
      s.setString(_appearanceKey, _appearance.name);
      s.setBool(_englishKey, _english);
      s.setBool(_onboardedKey, true);
    }
    notifyListeners();
  }

  void finishOnboarding() {
    _onboarded = true;
    _store?.setBool(_onboardedKey, true);
    notifyListeners();
  }
}
