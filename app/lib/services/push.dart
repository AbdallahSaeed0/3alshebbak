// The registration-token API is deprecated in favour of installation ids, but
// tokens are what the pipeline's FCM HTTP v1 sends address (src/fcm.ts).
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/prefs.dart';
import '../data/supabase_repository.dart';
import '../firebase_options.dart';

/// "Tickets are out" notifications. The phone registers its push token with
/// the films it follows and its cinemas (Supabase `register_device`); the
/// pipeline sends the notifications (scraper/src/notify.ts).
///
/// Everything here is a no-op until Firebase is configured
/// (firebase_options.dart), and on the web.
class Push {
  Push._();
  static final instance = Push._();

  static bool get available => firebaseOptions != null && !kIsWeb;

  Prefs? _prefs;
  String? _token;
  Timer? _debounce;

  /// Called with a film id when the user taps a notification.
  void Function(String movieId)? onOpenFilm;

  /// Starts listening if the user already allowed notifications; never asks.
  Future<void> start(Prefs prefs) async {
    if (!available || _prefs != null) return;
    _prefs = prefs;
    try {
      await Firebase.initializeApp(options: firebaseOptions);
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onMessageOpenedApp.listen(_opened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _opened(initial);
      messaging.onTokenRefresh.listen((t) {
        _token = t;
        _register();
      });
      prefs.addListener(_changed);
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        _token = await messaging.getToken();
        await _register();
      }
    } catch (e) {
      debugPrint('Push unavailable: $e');
    }
  }

  /// Asks for permission (Android 13+ / iOS show a dialog) and registers.
  /// Returns whether notifications are on.
  Future<bool> enable() async {
    if (!available || _prefs == null) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      _token = await FirebaseMessaging.instance.getToken();
      await _register();
      return _token != null;
    } catch (e) {
      debugPrint('Turning on notifications failed: $e');
      return false;
    }
  }

  void _opened(RemoteMessage message) {
    final movieId = message.data['movieId'];
    if (movieId is String) onOpenFilm?.call(movieId);
  }

  /// Picks change in bursts (starring a few cinemas): register once after.
  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), _register);
  }

  Future<void> _register() async {
    final token = _token;
    final prefs = _prefs;
    if (token == null || prefs == null) return;
    try {
      final res = await http.post(
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
          'p_following': prefs.following.toList(),
          'p_cinemas': prefs.myCinemas.toList(),
        }),
      );
      if (res.statusCode >= 300) {
        debugPrint('register_device: HTTP ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('register_device failed: $e');
    }
  }
}
