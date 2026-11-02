import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/app_data.dart';
import '../util/format.dart';
import '../util/i18n.dart';

/// Writes the next shows at my cinemas into the Android home-screen widget
/// (NextShowWidget.kt draws them). Called whenever showtimes load or my
/// cinemas change; the widget has no timer of its own.
Future<void> syncHomeWidget(AppData data) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final rows = [
      for (final s in data.nextAtMyCinemas(limit: 3))
        '${clock(s.wallClock)} ${period(s.wallClock)} · '
            '${data.movie(s.movieId).displayTitle} · ${data.cinema(s.cinemaId).label}',
    ];
    await HomeWidget.saveWidgetData(
      'next_title',
      tr('الجاي في سينماتك', 'Up next at your cinemas'),
    );
    await HomeWidget.saveWidgetData('next_rows', rows.join('\n'));
    await HomeWidget.saveWidgetData(
      'next_empty',
      tr(
        'مفيش حفلات جاية في سينماتك خلال ٢٤ ساعة',
        'No shows at your cinemas in the next 24 hours',
      ),
    );
    await HomeWidget.updateWidget(androidName: 'NextShowWidget');
  } catch (e) {
    debugPrint('Updating the home-screen widget failed: $e');
  }
}
