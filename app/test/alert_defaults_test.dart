import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shebbak/data/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new install hears about every film at every cinema', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    expect(prefs.everyFilm, isTrue);
    expect(prefs.allCinemaAlerts, isTrue);
    expect(prefs.everyFilmByDefault, isTrue);
    expect(prefs.allCinemasByDefault, isTrue);
  });

  test('picking a cinema narrows alerts to my cinemas, once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    prefs.setCinemas({'scene:cfc'});
    expect(prefs.allCinemaAlerts, isFalse);
    expect(prefs.everyFilm, isTrue);
    // Chosen again by hand afterwards: it stays.
    prefs.setAllCinemaAlerts(true);
    prefs.toggleCinema('vox:moe');
    expect(prefs.allCinemaAlerts, isTrue);
  });

  test('following a film narrows alerts to followed films, once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    prefs.toggleFollow('tmdb:1');
    expect(prefs.everyFilm, isFalse);
    expect(prefs.allCinemaAlerts, isTrue);
    prefs.setEveryFilm(true);
    prefs.toggleFollow('tmdb:2');
    expect(prefs.everyFilm, isTrue);
  });

  test(
    'turning notifications on keeps the default; the switch ends it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      prefs.setEveryFilm(true, chosen: false);
      expect(prefs.everyFilmByDefault, isTrue);
      prefs.setEveryFilm(true);
      expect(prefs.everyFilmByDefault, isFalse);
      prefs.toggleFollow('tmdb:1');
      expect(prefs.everyFilm, isTrue);
    },
  );

  test('the narrowing survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    (await Prefs.load())
      ..toggleFollow('tmdb:1')
      ..finishOnboarding();
    final again = await Prefs.load();
    expect(again.everyFilm, isFalse);
    expect(again.everyFilmByDefault, isFalse);
    expect(again.allCinemaAlerts, isTrue);
    expect(again.allCinemasByDefault, isTrue);
  });

  test('phones set up before this keep what they had', () async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final prefs = await Prefs.load();
    expect(prefs.everyFilm, isFalse);
    expect(prefs.allCinemaAlerts, isFalse);
    expect(prefs.everyFilmByDefault, isFalse);
  });
}
