import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// A cinema's site — booking a show, a cinema's page — opened over the app
/// (Chrome Custom Tabs on Android, Safari on iPhone) rather than in another
/// app: the person picks seats and pays there, then closes it and is back
/// where they were. It is the real browser, so card payments, Apple/Google
/// Pay and the site's own sign-in keep working.
Future<void> openSite(String url) async {
  final uri = Uri.parse(url);
  try {
    if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return;
  } catch (e) {
    debugPrint('In-app browser unavailable: $e');
  }
  // No in-app browser on this phone (or on the web): the usual browser.
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
