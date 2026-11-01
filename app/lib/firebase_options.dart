import 'package:firebase_core/firebase_core.dart';

/// Firebase, used only for push notifications ("tickets are out").
///
/// Null until a Firebase project is set up: the app then runs without push.
/// To turn it on, add an Android app with package `com.shebbak.shebbak` in the
/// Firebase console and copy its values here (or run `flutterfire configure`).
/// The pipeline needs the matching service account key as the repository
/// secret FIREBASE_SERVICE_ACCOUNT.
const FirebaseOptions? firebaseOptions = null;
