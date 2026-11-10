import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/supabase_repository.dart';
import 'app_version.dart';

/// Counts users without knowing who they are: the install makes up a random
/// id once, and reports it with the platform and app version the first time
/// the app opens each day (Supabase `record_open`). Nothing else is sent.
/// Release builds on phones only, so test runs don't count.
class Usage {
  Usage._();

  static const _idKey = 'install_id';
  static const _dayKey = 'install_reported_day';

  static bool get _counts =>
      kReleaseMode &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Reports today's open, once a day. Never throws.
  static Future<void> recordOpen({http.Client? client}) async {
    if (!_counts) return;
    try {
      final store = await SharedPreferences.getInstance();
      final today = _cairoDay(DateTime.now());
      if (store.getString(_dayKey) == today) return;
      final id = store.getString(_idKey) ?? _newId();
      await store.setString(_idKey, id);
      final c = client ?? http.Client();
      try {
        final res = await c
            .post(
              Uri.parse(
                '${SupabaseShowtimesRepository.url}/rest/v1/rpc/record_open',
              ),
              headers: {
                ...SupabaseShowtimesRepository.headers,
                'Content-Profile': 'shebbak',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'p_install': id,
                'p_platform': defaultTargetPlatform == TargetPlatform.iOS
                    ? 'ios'
                    : 'android',
                'p_version': await appVersion(),
              }),
            )
            .timeout(const Duration(seconds: 15));
        // Before the table exists the call fails; try again next open.
        if (res.statusCode < 300) await store.setString(_dayKey, today);
      } finally {
        if (client == null) c.close();
      }
    } catch (e) {
      debugPrint('Usage not recorded: $e');
    }
  }

  static String _newId() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Cairo is UTC+2 in winter, +3 in summer; the day only needs to roll over
  /// near midnight, so +2 is close enough for a once-a-day report.
  static String _cairoDay(DateTime now) => now
      .toUtc()
      .add(const Duration(hours: 2))
      .toIso8601String()
      .substring(0, 10);
}
