import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/prefs.dart';

/// Why we couldn't get a fix — each gets its own wording on screen.
enum LocationProblem { serviceOff, denied, deniedForever, unavailable }

/// Asks for the phone's location once (approximate is enough: we only sort
/// cinemas by distance). Returns the spot, or why there isn't one.
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
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (e) {
      debugPrint('No fresh location ($e); trying the last known one');
      if (!kIsWeb) position = await Geolocator.getLastKnownPosition();
    }
    return position == null
        ? (null, LocationProblem.unavailable)
        : ((lat: position.latitude, lng: position.longitude), null);
  } catch (e) {
    debugPrint('Location failed: $e');
    return (null, LocationProblem.unavailable);
  }
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
  LocationProblem.serviceOff => 'اللوكيشن مقفول في الموبايل. افتحه وجرّب تاني.',
  LocationProblem.denied => 'من غير اللوكيشن مش هنعرف أقرب سينما ليك.',
  LocationProblem.deniedForever =>
    'اللوكيشن مرفوض للتطبيق. تقدر تسمح بيه من الإعدادات.',
  LocationProblem.unavailable => 'معرفناش نحدد مكانك دلوقتي. جرّب تاني.',
};

/// Reads the location again and keeps it (Cinemas tab's "near me" button).
Future<LocationProblem?> refreshSpot(Prefs prefs) async {
  final (spot, problem) = await locateOnce();
  if (spot != null) prefs.setSpot(spot);
  return problem;
}
