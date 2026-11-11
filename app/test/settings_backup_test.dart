import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shebbak/data/prefs.dart';
import 'package:shebbak/services/settings_backup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('shebbak/device');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'installKey' ? 'a1b2c3d4e5f60718' : null,
        );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('the backup key is a hash, the same on every reinstall', () {
    final key = SettingsBackup.ownerFor('a1b2c3d4e5f60718');
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(key, SettingsBackup.ownerFor('a1b2c3d4e5f60718'));
    expect(key, isNot(contains('a1b2c3d4e5f60718')));
  });

  test('a backup round-trips everything but the location', () {
    final before = Prefs.memory(
      cinemas: {'elcinema:americana-plaza'},
      following: {'tmdb:1'},
      spot: (lat: 30.0, lng: 31.0),
      english: true,
      everyFilm: true,
      homeCity: 'Cairo',
      appearance: Appearance.dark,
    );
    final backup = before.toBackup();
    expect(backup.containsKey('spot'), isFalse);
    final after = Prefs.memory(onboarded: false)
      ..restore(jsonDecode(jsonEncode(backup)) as Map<String, dynamic>);
    expect(after.onboarded, isTrue);
    expect(after.myCinemas, {'elcinema:americana-plaza'});
    expect(after.following, {'tmdb:1'});
    expect(after.everyFilm, isTrue);
    expect(after.english, isTrue);
    expect(after.homeCity, 'Cairo');
    expect(after.appearance, Appearance.dark);
    expect(after.spot, isNull);
  });

  test(
    'a fresh install gets its settings back and saves nothing first',
    () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add(req.url.pathSegments.last);
        if (req.url.path.endsWith('load_settings')) {
          return http.Response(
            jsonEncode({
              'cinemas': ['scene:cfc'],
              'following': ['tmdb:9'],
              'english': false,
            }),
            200,
          );
        }
        return http.Response('', 204);
      });
      final prefs = Prefs.memory(onboarded: false);
      final restored = await SettingsBackup.start(prefs, client: client);
      expect(restored, isTrue);
      expect(prefs.myCinemas, {'scene:cfc'});
      expect(prefs.following, {'tmdb:9'});
      expect(calls, ['load_settings']); // no save of the defaults
    },
  );

  test('a fresh install with no backup stays in onboarding', () async {
    final client = MockClient((req) async => http.Response('null', 200));
    final prefs = Prefs.memory(onboarded: false);
    expect(await SettingsBackup.start(prefs, client: client), isFalse);
    expect(prefs.onboarded, isFalse);
  });
}
