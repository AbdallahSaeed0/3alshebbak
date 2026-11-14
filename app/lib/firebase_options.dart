import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase, for push notifications ("tickets are out") and crash reports
/// (services/crash_reports.dart).
///
/// Project `shebbak-app`, with an Android and an Apple app. On the web this is
/// null and the app runs without push. iOS delivery goes through the APNs key
/// uploaded in the Firebase console (Cloud Messaging > Apple app).
/// The pipeline sends with the project's service account key, the repository
/// secret FIREBASE_SERVICE_ACCOUNT.
FirebaseOptions? get firebaseOptions => kIsWeb
    ? null
    : switch (defaultTargetPlatform) {
        TargetPlatform.android => _android,
        TargetPlatform.iOS => _ios,
        _ => null,
      };

// Client config, not a secret: it ships inside every APK.
const _android = FirebaseOptions(
  apiKey: 'AIzaSyCxngP-uYfCAPvqYxUCUNlkGPUFa5r0afw',
  appId: '1:396673822188:android:1f0e1af6a21704022b24c9',
  messagingSenderId: '396673822188',
  projectId: 'shebbak-app',
  storageBucket: 'shebbak-app.firebasestorage.app',
);

// Client config for the Apple app, not a secret: it ships inside every IPA.
const _ios = FirebaseOptions(
  apiKey: 'AIzaSyBoyCOq9h9CANb-3ioibu3gkB2rkB13ZwA',
  appId: '1:396673822188:ios:26097ba5b00ad8452b24c9',
  messagingSenderId: '396673822188',
  projectId: 'shebbak-app',
  storageBucket: 'shebbak-app.firebasestorage.app',
  iosBundleId: 'com.shebbak.shebbak',
);

Future<FirebaseApp>? _firebase;

/// Starts Firebase once, for whichever needs it first (push or crash
/// reports). A failed start is tried again next call.
Future<FirebaseApp> ensureFirebase() => _firebase ??=
    Firebase.initializeApp(options: firebaseOptions).catchError((Object e) {
      _firebase = null;
      throw e;
    });
