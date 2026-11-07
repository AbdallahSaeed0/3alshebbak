import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "0.2.0": the installed app's version.
Future<String> appVersion() async => (await PackageInfo.fromPlatform()).version;

/// Built for Google Play (`--dart-define=STORE=play`). Play updates the app
/// itself and forbids apps updating outside it, so the GitHub check is off.
const fromPlayStore = String.fromEnvironment('STORE') == 'play';

/// A newer APK on the GitHub releases page.
typedef AppUpdate = ({String version, Uri download, List<String> notes});

/// The release's "what's new" bullets ("- …" lines), without markdown.
List<String> releaseNotes(String? body) => [
  for (final line in (body ?? '').split('\n'))
    if (line.trimLeft().startsWith('- '))
      line
          .trimLeft()
          .substring(2)
          .replaceAll('**', '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
];

const _releases =
    'https://api.github.com/repos/AbdallahSaeed0/3alshebbak/releases?per_page=5';

/// Mentioned at most once a day per version, so it nudges without nagging.
const _shownKey = 'update_shown';

/// The newest release if it's newer than this app and has an APK, else null.
/// Testers install from GitHub releases, which can't update the app by
/// itself, so the app has to say so. Android only: web is always current.
Future<AppUpdate?> checkForUpdate({bool ignoreShown = false}) async {
  if (kIsWeb ||
      fromPlayStore ||
      defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  try {
    final res = await http
        .get(
          Uri.parse(_releases),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final releases = (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>();
    final release = releases.where((r) => r['draft'] != true).firstOrNull;
    if (release == null) return null;
    final latest = (release['tag_name'] as String).replaceFirst('v', '');
    if (!isNewer(latest, await appVersion())) return null;
    final apk = (release['assets'] as List)
        .cast<Map<String, dynamic>>()
        .where((a) => (a['name'] as String).endsWith('.apk'))
        .firstOrNull;
    if (apk == null) return null;

    if (!ignoreShown) {
      final store = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (store.getString(_shownKey) == '$latest|$today') return null;
      await store.setString(_shownKey, '$latest|$today');
    }
    return (
      version: latest,
      download: Uri.parse(apk['browser_download_url'] as String),
      notes: releaseNotes(release['body'] as String?),
    );
  } catch (e) {
    debugPrint('Update check failed: $e');
    return null;
  }
}

/// Whether version [a] ("0.2.0") is after [b], part by part.
bool isNewer(String a, String b) {
  List<int> parts(String v) =>
      v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}
