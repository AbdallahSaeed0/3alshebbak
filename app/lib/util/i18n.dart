// The app speaks Egyptian Arabic, or English when the user picks it in
// Settings. Strings sit next to each other where they're used:
// tr('الحفلات', 'Showtimes').

/// Set from Prefs.english before every build (main.dart).
abstract final class Lang {
  static bool english = false;
}

String tr(String arabic, String english) => Lang.english ? english : arabic;
