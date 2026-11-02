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
    prefs.toggleFollow(movieId);
    final following = prefs.isFollowing(movieId);
    if (!notifications.supported) {
      if (following && context.mounted) {
        _say(
          context,
          tr(
            'بتتابع الفيلم. الإشعارات مش متاحة على النسخة دي.',
            'Following this film. Alerts are unavailable on this platform.',
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
            ? tr('بطّلت متابعة الفيلم', 'Unfollowed this film')
            : tr(
                'اتلغت المتابعة على الموبايل، لكن مزامنتها فشلت. جرّب تاني.',
                'Unfollowed on this phone, but syncing failed. Try again.',
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
                        ? tr(
                            'تمام، متابعة الجهاز اتزامنت',
                            'Device preferences synced',
                          )
                        : tr(
                            'المزامنة ما كملتش. اتأكد من النت وجرّب تاني.',
                            'Sync failed. Check your connection and retry.',
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
      FollowAlertResult.enabled =>
        prefs.myCinemas.isEmpty
            ? tr(
                'هيوصلك إشعار لما الحجز يفتح في أي سينما',
                'You’ll get an alert when booking opens at any cinema',
              )
            : tr(
                'هيوصلك إشعار لما الحجز يفتح في السينمات اللي مختارها',
                'You’ll get an alert when booking opens at your selected cinemas',
              ),
      FollowAlertResult.denied => tr(
        'بتتابع الفيلم، بس إذن الإشعارات مقفول. افتحه من إعدادات الموبايل.',
        'Following this film, but notification permission is off. Enable it in your phone settings.',
      ),
      FollowAlertResult.failed => tr(
        'بتتابع الفيلم، لكن تفعيل الإشعارات ما كملش. اتأكد من النت وجرّب تاني.',
        'Following this film, but alerts could not be activated. Check your connection and retry.',
      ),
      FollowAlertResult.unavailable => tr(
        'بتتابع الفيلم. الإشعارات مش متاحة على النسخة دي.',
        'Following this film. Alerts are unavailable on this platform.',
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
                  ? tr('تمام، إشعارات الفيلم اتفعّلت', 'Film alerts enabled')
                  : tr(
                      'تفعيل الإشعارات ما كملش. جرّب من الإعدادات.',
                      'Alerts could not be enabled. Try from settings.',
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
