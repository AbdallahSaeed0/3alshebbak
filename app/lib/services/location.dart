import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/prefs.dart';
import '../util/i18n.dart';

/// Why we couldn't get a fix — each gets its own wording on screen.
enum LocationProblem { serviceOff, denied, deniedForever, unavailable }

/// Asks for the phone's location once. Precise when the user allows it, since
/// the map pins "you are here"; approximate still works for sorting cinemas.
/// Returns the spot, or why there isn't one.
Future<(Spot?, LocationProblem?)> locateOnce() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (null, LocationProblem.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return (null, LocationProblem.deniedForever);
    }
    if (permission == LocationPermission.denied) {
      return (null, LocationProblem.denied);
    }
    // Allowed before as approximate only (the app used to ask for no more):
    // offer the upgrade, since the map's dot can then be kilometres off.
    if (!kIsWeb &&
        await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced) {
      await Geolocator.requestPermission();
    }
    final spot = await _currentSpot();
    return spot == null ? (null, LocationProblem.unavailable) : (spot, null);
  } catch (e) {
    debugPrint('Location failed: $e');
    return (null, LocationProblem.unavailable);
  }
}

const _staleAfter = Duration(minutes: 15);

/// A fresh fix, or a recent last-known one; null when neither is to be had.
Future<Spot?> _currentSpot() async {
  Position? position;
  try {
    position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  } catch (e) {
    debugPrint('No fresh location ($e); trying the last known one');
    if (!kIsWeb) {
      position = await Geolocator.getLastKnownPosition().catchError(
        (_) => null,
      );
    }
    // An old fix may be from another part of town; better none than wrong.
    if (position != null &&
        DateTime.now().difference(position.timestamp) > _staleAfter) {
      position = null;
    }
  }
  return position == null
      ? null
      : (lat: position.latitude, lng: position.longitude);
}

/// Opens the system settings page that can fix [problem].
Future<void> openFixFor(LocationProblem problem) async {
  if (problem == LocationProblem.serviceOff) {
    await Geolocator.openLocationSettings();
  } else {
    await Geolocator.openAppSettings();
  }
}

String describe(LocationProblem problem) => switch (problem) {
  LocationProblem.serviceOff => tr(
    'اللوكيشن مقفول في الموبايل. افتحه وجرّب تاني.',
    'Location is off on your phone. Turn it on and try again.',
  ),
  LocationProblem.denied => tr(
    'من غير اللوكيشن مش هنعرف أقرب سينما ليك.',
    'Without your location we can\'t find your nearest cinema.',
  ),
  LocationProblem.deniedForever => tr(
    'اللوكيشن مرفوض للتطبيق. تقدر تسمح بيه من الإعدادات.',
    'Location is blocked for the app. You can allow it in settings.',
  ),
  LocationProblem.unavailable => tr(
    'معرفناش نحدد مكانك دلوقتي. جرّب تاني.',
    'We couldn\'t find your location just now. Try again.',
  ),
};

/// Reads the location again and keeps it (Cinemas tab's "near me" button).
Future<LocationProblem?> refreshSpot(Prefs prefs) async {
  final (spot, problem) = await locateOnce();
  if (spot != null) prefs.setSpot(spot);
  return problem;
}

/// Updates the kept spot without asking for anything: only when location is
/// already allowed and on. The spot is otherwise from whenever it was last
/// read (onboarding, say), which is wrong once the user has moved.
Future<void> refreshSpotQuietly(Prefs prefs) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return;
    }
  } catch (_) {
    return;
  }
  final spot = await _currentSpot();
  if (spot != null) prefs.setSpot(spot);
}
