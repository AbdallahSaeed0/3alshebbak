import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/prefs.dart';
import '../util/i18n.dart';
import 'push.dart';

final _pending = <(Prefs, String)>{};

/// Following a film also offers to turn on its ticket alerts.
Future<void> toggleFilmFollow(
  BuildContext context,
  Prefs prefs,
  String movieId, {
  FilmAlerts? alerts,
}) async {
  final key = (prefs, movieId);
  if (!_pending.add(key)) return;
  try {
    final notifications = alerts ?? Push.instance;
    // The first film followed ends the "every film" default.
    final narrowed = prefs.everyFilmByDefault && !prefs.isFollowing(movieId);
    prefs.toggleFollow(movieId);
    final following = prefs.isFollowing(movieId);
    if (!notifications.supported) {
      if (following && context.mounted) {
        _say(
          context,
          tr(
            'بتتابع الفيلم. الإشعارات مش متاحة على النسخة دي.',
            'You’re following this film. Notifications don’t work on this version.',
          ),
        );
      }
      return;
    }

    if (!following) {
      final synced = await notifications.syncPreferences();
      if (!context.mounted) return;
      _say(
        context,
        synced
            ? tr('بطّلت متابعة الفيلم', 'You stopped following this film')
            : tr(
                'اتلغت المتابعة على الموبايل، لكن مزامنتها فشلت. جرّب تاني.',
                'Unfollowed on this phone, but it didn’t sync. Try again.',
              ),
        action: synced
            ? null
            : SnackBarAction(
                label: tr('حاول تاني', 'Retry'),
                onPressed: () async {
                  final synced = await notifications.syncPreferences();
                  if (!context.mounted) return;
                  _say(
                    context,
                    synced
                        ? tr('تمام، متابعة الجهاز اتزامنت', 'All synced')
                        : tr(
                            'المزامنة ما كملتش. اتأكد من النت وجرّب تاني.',
                            'Didn’t sync. Check your internet and try again.',
                          ),
                  );
                },
              ),
      );
      return;
    }

    final result = await notifications.enableForFollow();
    if (!context.mounted || !prefs.isFollowing(movieId)) return;
    final message = switch (result) {
      FollowAlertResult.enabled when narrowed => tr(
        'هيوصلك إشعار لما الحجز يفتح. ومن دلوقتي الإشعارات للأفلام اللي بتتابعها بس، وتقدر ترجّع «كل الأفلام» من الإعدادات.',
        'We’ll let you know when booking opens. From now on you’ll only hear about films you follow; turn “Every film” back on in Settings.',
      ),
      FollowAlertResult.enabled =>
        prefs.myCinemas.isEmpty
            ? tr(
                'هيوصلك إشعار لما الحجز يفتح في أي سينما',
                'We’ll let you know when booking opens at any cinema',
              )
            : tr(
                'هيوصلك إشعار لما الحجز يفتح في السينمات اللي مختارها',
                'We’ll let you know when booking opens at your cinemas',
              ),
      FollowAlertResult.denied => tr(
        'بتتابع الفيلم، بس إذن الإشعارات مقفول. افتحه من إعدادات الموبايل.',
        'You’re following this film, but notifications are off. Turn them on in your phone’s settings.',
      ),
      FollowAlertResult.failed => tr(
        'بتتابع الفيلم، لكن تفعيل الإشعارات ما كملش. اتأكد من النت وجرّب تاني.',
        'You’re following this film, but we couldn’t turn on notifications. Check your internet and try again.',
      ),
      FollowAlertResult.unavailable => tr(
        'بتتابع الفيلم. الإشعارات مش متاحة على النسخة دي.',
        'You’re following this film. Notifications don’t work on this version.',
      ),
    };
    _say(
      context,
      message,
      action: switch (result) {
        FollowAlertResult.denied => SnackBarAction(
          label: tr('الإعدادات', 'Settings'),
          onPressed: () {
            Geolocator.openAppSettings();
          },
        ),
        FollowAlertResult.failed => SnackBarAction(
          label: tr('حاول تاني', 'Retry'),
          onPressed: () async {
            if (!prefs.isFollowing(movieId)) return;
            final retry = await notifications.enableForFollow();
            if (!context.mounted || !prefs.isFollowing(movieId)) return;
            _say(
              context,
              retry == FollowAlertResult.enabled
                  ? tr(
                      'تمام، إشعارات الفيلم اتفعّلت',
                      'Done, notifications are on for this film',
                    )
                  : tr(
                      'تفعيل الإشعارات ما كملش. جرّب من الإعدادات.',
                      'Couldn’t turn on notifications. Try from Settings.',
                    ),
            );
          },
        ),
        _ => null,
      },
    );
  } finally {
    _pending.remove(key);
  }
}

void _say(BuildContext context, String message, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Keeps existing button styling while showing and locking pending work.
class FilmFollowAction extends StatefulWidget {
  const FilmFollowAction({
    super.key,
    required this.prefs,
    required this.movieId,
    required this.builder,
    this.alerts,
  });
  final Prefs prefs;
  final String movieId;
  final FilmAlerts? alerts;
  final Widget Function(VoidCallback? onPressed, bool busy) builder;
  @override
  State<FilmFollowAction> createState() => _FilmFollowActionState();
}

class _FilmFollowActionState extends State<FilmFollowAction> {
  bool _busy = false;
  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await toggleFilmFollow(
        context,
        widget.prefs,
        widget.movieId,
        alerts: widget.alerts,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(_busy ? null : _toggle, _busy);
}
