import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
}

Future<void> _openYouTube(String key) => launchUrl(
  Uri.parse('https://www.youtube.com/watch?v=$key'),
  mode: LaunchMode.externalApplication,
);

class _TrailerPopup extends StatelessWidget {
  const _TrailerPopup({required this.movie, required this.youTubeKey});

  final Movie movie;
  final String youTubeKey;

  /// YouTube's embedded player, sized to the popup. Loaded as a page "from"
  /// youtube.com: the player refuses to start without a web origin.
  String get _page =>
      '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe src="https://www.youtube.com/embed/$youTubeKey?autoplay=1&playsinline=1&rel=0&modestbranding=1"
 allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
</body></html>''';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
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
                  baseUrl: WebUri('https://www.youtube.com'),
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
