// The registration-token API is deprecated in favour of installation ids, but
// tokens are what the pipeline's FCM HTTP v1 sends address (src/fcm.ts).
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:url_launcher/url_launcher.dart';

import '../data/prefs.dart';
import 'app_version.dart';
import '../data/supabase_repository.dart';
import '../firebase_options.dart';

enum FollowAlertResult { enabled, denied, unavailable, failed }

abstract interface class FilmAlerts {
  bool get supported;
  Future<FollowAlertResult> enableForFollow();
  Future<bool> syncPreferences();
}

/// "Tickets are out" notifications. The phone registers its push token with
/// the films it follows and its cinemas (Supabase `register_device`); the
/// pipeline sends the notifications (scraper/src/notify.ts).
///
/// Everything here is a no-op until Firebase is configured
/// (firebase_options.dart), and on the web.
class Push implements FilmAlerts {
  Push._();
  static final instance = Push._();

  static bool get available => firebaseOptions != null && !kIsWeb;

  Prefs? _prefs;
  String? _token;
  Timer? _debounce;
  Future<void>? _starting;
  Future<FollowAlertResult>? _enabling;
  Future<bool>? _registration;
  bool _initialized = false;

  @override
  bool get supported => available;

  /// Called with a film id when the user taps a notification.
  void Function(String movieId)? onOpenFilm;

  /// Starts listening if the user already allowed notifications; never asks.
  Future<void> start(Prefs prefs) {
    if (!available) return Future.value();
    if (!identical(_prefs, prefs)) {
      _prefs?.removeListener(_changed);
      prefs.addListener(_changed);
    }
    _prefs = prefs;
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      await Firebase.initializeApp(options: firebaseOptions);
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onMessageOpenedApp.listen(_opened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _opened(initial);
      messaging.onTokenRefresh.listen((t) {
        _token = t;
        syncPreferences();
      });
      _initialized = true;
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        _token = await messaging.getToken();
        await syncPreferences();
      }
    } catch (e) {
      debugPrint('Push unavailable: $e');
      if (!_initialized) _starting = null;
    }
  }

  /// Asks for permission (Android 13+ / iOS show a dialog) and registers.
  /// Returns whether notifications are on.
  Future<bool> enable() async =>
      await enableForFollow() == FollowAlertResult.enabled;

  @override
  Future<FollowAlertResult> enableForFollow() {
    return _enabling ??= _enable().whenComplete(() => _enabling = null);
  }

  Future<FollowAlertResult> _enable() async {
    final prefs = _prefs;
    if (!available || prefs == null) return FollowAlertResult.unavailable;
    try {
      await start(prefs);
      if (!_initialized) return FollowAlertResult.failed;
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return FollowAlertResult.denied;
      }
      _token = await FirebaseMessaging.instance.getToken();
      return await syncPreferences()
          ? FollowAlertResult.enabled
          : FollowAlertResult.failed;
    } catch (e) {
      debugPrint('Turning on notifications failed: $e');
      return FollowAlertResult.failed;
    }
  }

  void _opened(RemoteMessage message) {
    final movieId = message.data['movieId'];
    if (movieId is String) onOpenFilm?.call(movieId);
    // "A new version is out" (scraper/scripts/announce-release.ts): the
    // download page, which always points at the newest APK.
    final url = message.data['url'];
    if (message.data['type'] == 'update' && url is String && !fromPlayStore) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  /// Picks change in bursts (starring a few cinemas): register once after.
  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncPreferences);
  }

  /// Serialize writes so an older request cannot restore an unfollowed film.
  @override
  Future<bool> syncPreferences() {
    _debounce?.cancel();
    return _registration = (_registration ?? Future.value(true)).then(
      (_) => _register(),
    );
  }

  /// Returning from phone settings can grant permission without another prompt.
  Future<void> refresh() async {
    final prefs = _prefs;
    if (!available || prefs == null) return;
    try {
      await start(prefs);
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        _token = await FirebaseMessaging.instance.getToken();
        await syncPreferences();
      }
    } catch (e) {
      debugPrint('Refreshing push registration failed: $e');
    }
  }

  Future<bool> _register() async {
    final token = _token;
    final prefs = _prefs;
    if (token == null || prefs == null) return false;
    final client = http.Client();
    try {
      final res = await client
          .post(
            Uri.parse(
              '${SupabaseShowtimesRepository.url}/rest/v1/rpc/register_device',
            ),
            headers: {
              ...SupabaseShowtimesRepository.headers,
              'Content-Profile': 'shebbak',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'p_token': token,
              'p_platform': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
              // "*" asks the server for every film, "@all-cinemas" for every
              // cinema, not only starred ones (scraper/src/notify.ts).
              'p_following': [
                ...prefs.following,
                if (prefs.everyFilm) '*',
                if (prefs.allCinemaAlerts) '@all-cinemas',
                // Play installs update through Play, not GitHub's APK.
                if (fromPlayStore) '@play',
              ],
              'p_cinemas': prefs.myCinemas.toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 300) {
        debugPrint('register_device: HTTP ${res.statusCode} ${res.body}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('register_device failed: $e');
      return false;
    } finally {
      client.close();
    }
  }
}
