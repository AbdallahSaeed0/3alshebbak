import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../theme.dart';
import '../util/i18n.dart';

/// Plays a film's YouTube trailer in a popup over the app. On the web (and
/// anywhere without a web view) it opens YouTube instead.
Future<void> showTrailer(BuildContext context, Movie movie) async {
  final key = movie.trailerKey;
  if (key == null) return;
  final phone =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (!phone) {
    await _openYouTube(key);
    return;
  }
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _TrailerPopup(movie: movie, youTubeKey: key),
  );
  // Closed while full screen (the back button): portrait and bars again.
  await _fullScreen(false);
}

Future<void> _openYouTube(String key) => launchUrl(
  Uri.parse('https://www.youtube.com/watch?v=$key'),
  mode: LaunchMode.externalApplication,
);

/// Landscape and immersive while the player is full screen; the app's usual
/// orientations and bars otherwise.
Future<void> _fullScreen(bool on) async {
  if (on) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class _TrailerPopup extends StatelessWidget {
  const _TrailerPopup({required this.movie, required this.youTubeKey});

  final Movie movie;
  final String youTubeKey;

  /// Who the player is embedded by. YouTube's player shows "Video
  /// unavailable" (errors 152/153) unless the embedding page identifies
  /// itself with a Referer; for an app's web view its terms ask for
  /// https:// followed by the app id. Posing as youtube.com no longer works.
  static const _origin = 'https://com.shebbak.shebbak';

  /// YouTube's embedded player, sized to the popup.
  String get _page =>
      '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe src="https://www.youtube.com/embed/$youTubeKey?autoplay=1&playsinline=1&rel=0&modestbranding=1&enablejsapi=1&origin=$_origin&widget_referrer=$_origin"
 referrerpolicy="strict-origin-when-cross-origin"
 allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
</body></html>''';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      // Nearly the screen's width: the trailer is the point of the popup.
      insetPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    movie.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(18),
                  ),
                ),
                IconButton(
                  tooltip: tr('قفل', 'Close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: _page,
                  baseUrl: WebUri(_origin),
                ),
                initialSettings: InAppWebViewSettings(
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  iframeAllowFullscreen: true,
                  transparentBackground: true,
                  supportZoom: false,
                ),
                // Links inside the player (the YouTube logo, "watch on
                // YouTube") go to the YouTube app, not into the popup.
                // YouTube's own full-screen button: sideways and without
                // the status and navigation bars, back again on exit.
                onEnterFullscreen: (_) => _fullScreen(true),
                onExitFullscreen: (_) => _fullScreen(false),
                shouldOverrideUrlLoading: (_, action) async {
                  final url = action.request.url;
                  if (action.isForMainFrame &&
                      url != null &&
                      url.host.contains('youtube.com') &&
                      !url.path.startsWith('/embed')) {
                    await _openYouTube(youTubeKey);
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _openYouTube(youTubeKey);
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(tr('افتح في YouTube', 'Open in YouTube')),
          ),
        ],
      ),
    );
  }
}
