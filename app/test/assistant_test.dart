import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/app_data.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/data/prefs.dart';
import 'package:shebbak/data/repository.dart';
import 'package:shebbak/screens/assistant_screen.dart';
import 'package:shebbak/widgets/share_card.dart';

Showtime _show(String start) => Showtime.fromJson({
  'cinemaId': 'scene:cfc',
  'businessDate': '2026-11-01',
  'start': start,
  'format': 'IMAX',
}, 'local:clayface');

void main() {
  final data = AppData(
    CatalogData(
      cinemas: {
        'scene:cfc': const Cinema(
          id: 'scene:cfc',
          chain: 'Scene',
          name: 'Cairo Festival City',
          city: 'Cairo',
        ),
      },
      movies: {
        'local:clayface': const Movie(id: 'local:clayface', title: 'Clayface'),
      },
      showtimes: [
        _show('2026-11-01T19:30:00+02:00'),
        _show('2026-11-01T22:00:00+02:00'),
      ],
    ),
    Prefs.memory(cinemas: {'scene:cfc'}),
    now: DateTime.parse('2026-11-01T18:45:00+02:00'),
  );

  Widget app(Widget child) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: AppScope(data: data, child: child),
    ),
  );

  testWidgets('the assistant gets to a film\'s times by taps alone', (
    tester,
  ) async {
    await tester.pumpWidget(app(const AssistantScreen()));
    await tester.tap(find.text('مواعيد فيلم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('القاهرة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clayface'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('نوفمبر').last);
    await tester.pumpAndSettle();
    expect(find.text('7:30'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('2 حفلات في 1 سينما'), findsOneWidget);
    expect(find.text('من الأول'), findsOneWidget);
  });

  testWidgets('the share card renders to a picture', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: ShowtimesCard(
                movie: data.movie('local:clayface'),
                shows: data.catalog.showtimes,
                heading: 'نروح سوا؟',
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final png = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    expect(png!.lengthInBytes, greaterThan(1000));
  });
}
