import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase, used only for push notifications ("tickets are out").
///
/// Project `shebbak-app`. Only Android is registered so far; elsewhere this is
/// null and the app runs without push. For iOS, add an Apple app in the
/// Firebase console (and an APNs key) and return its values here.
/// The pipeline sends with the project's service account key, the repository
/// secret FIREBASE_SERVICE_ACCOUNT.
FirebaseOptions? get firebaseOptions =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? _android
    : null;

// Client config, not a secret: it ships inside every APK.
const _android = FirebaseOptions(
  apiKey: 'AIzaSyCxngP-uYfCAPvqYxUCUNlkGPUFa5r0afw',
  appId: '1:396673822188:android:1f0e1af6a21704022b24c9',
  messagingSenderId: '396673822188',
  projectId: 'shebbak-app',
  storageBucket: 'shebbak-app.firebasestorage.app',
);
