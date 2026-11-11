import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/prefs.dart';
import '../data/supabase_repository.dart';

/// Keeps the settings (cinemas, followed films, alert choices, language,
/// look) on the server under a key only this phone can make, so they come
/// back when the app is deleted and installed again. The key is a SHA-256 of
/// an id that survives a reinstall (Android's ANDROID_ID for this app; on
/// iPhone a random id in the Keychain, see AppDelegate.swift); the id never
/// leaves the phone. Location is never backed up (Prefs.toBackup).
class SettingsBackup {
  SettingsBackup._();

  static const _device = MethodChannel('shebbak/device');
  static Timer? _debounce;
  static String? _owner;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// The backup key for an install key; the same on every reinstall.
  @visibleForTesting
  static String ownerFor(String installKey) =>
      sha256.convert(utf8.encode('3alshebbak-settings:$installKey')).toString();

  /// Restores a backup into a fresh install's settings, then keeps the backup
  /// up to date. Returns whether settings were restored. Never throws.
  static Future<bool> start(Prefs prefs, {http.Client? client}) async {
    if (!_supported) return false;
    var restored = false;
    try {
      final key = await _device.invokeMethod<String>('installKey');
      if (key == null || key.isEmpty) return false;
      _owner = ownerFor(key);
      // Not onboarded: a fresh install, or one that was never set up. If this
      // phone had the app before, its settings are waiting.
      if (!prefs.onboarded) {
        final saved = await _call('load_settings', {'p_owner': _owner}, client);
        if (saved is Map<String, dynamic> && saved.isNotEmpty) {
          prefs.restore(saved);
          restored = true;
        }
      } else {
        // Settings from before this version: back them up once.
        unawaited(_save(prefs, client));
      }
    } catch (e) {
      debugPrint('Settings backup unavailable: $e');
    }
    prefs.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 4), () => _save(prefs, client));
    });
    return restored;
  }

  static Future<void> _save(Prefs prefs, http.Client? client) async {
    // A fresh install's defaults must never replace the real settings.
    if (_owner == null || !prefs.onboarded) return;
    try {
      await _call('save_settings', {
        'p_owner': _owner,
        'p_settings': prefs.toBackup(),
        'p_platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      }, client);
    } catch (e) {
      debugPrint('Settings not backed up: $e');
    }
  }

  static Future<Object?> _call(
    String function,
    Map<String, Object?> args,
    http.Client? client,
  ) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            Uri.parse(
              '${SupabaseShowtimesRepository.url}/rest/v1/rpc/$function',
            ),
            headers: {
              ...SupabaseShowtimesRepository.headers,
              'Content-Profile': 'shebbak',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(args),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 300) {
        throw Exception('$function: HTTP ${res.statusCode}');
      }
      final body = utf8.decode(res.bodyBytes);
      return body.isEmpty ? null : jsonDecode(body);
    } finally {
      if (client == null) c.close();
    }
  }
}
