import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Crash reports through Firebase Crashlytics: what broke, where in the code,
/// on which phone model and app version. No account, name, location or
/// settings go with them. Release builds on phones only, so a crash while
/// developing isn't reported.
class CrashReports {
  CrashReports._();

  static bool get _reports =>
      kReleaseMode && !kIsWeb && firebaseOptions != null;

  /// Catches every error from here on: the framework's (a widget that fails
  /// to build) and uncaught async ones. Never throws.
  static Future<void> start() async {
    if (!_reports) return;
    try {
      await ensureFirebase();
      final crashlytics = FirebaseCrashlytics.instance;
      FlutterError.onError = crashlytics.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('Crash reports unavailable: $e');
    }
  }
}
