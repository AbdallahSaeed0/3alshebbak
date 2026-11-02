import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/app_data.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/data/prefs.dart';
import 'package:shebbak/data/repository.dart';
import 'package:shebbak/screens/home_screen.dart';
import 'package:shebbak/util/format.dart';

Showtime _show(
  String start, {
  String cinema = 'scene:cfc',
  String movie = 'local:clayface',
}) => Showtime.fromJson({
  'cinemaId': cinema,
  'businessDate': '2026-11-01',
  'start': start,
  'format': '2D · IMAX',
}, movie);

void main() {
  final catalog = CatalogData(
    cinemas: {
      'scene:cfc': const Cinema(
        id: 'scene:cfc',
        chain: 'Scene',
        name: 'Cairo Festival City',
      ),
    },
    movies: {
      'local:clayface': const Movie(id: 'local:clayface', title: 'Clayface'),
    },
    showtimes: [
      _show('2026-11-01T19:30:00+02:00'),
      _show('2026-11-01T22:00:00+02:00'),
      _show('2026-11-02T00:30:00+02:00'),
    ],
  );
  // 6:45 PM Cairo.
  final data = AppData(
    catalog,
    Prefs.memory(cinemas: {'scene:cfc'}),
    now: DateTime.parse('2026-11-01T18:45:00+02:00'),
  );

  test('a 12:30 AM show still belongs to the day before', () {
    expect(data.today, '2026-11-01');
    expect(data.showingToday().single.showtimes.length, 3);
  });

  test('up next is each film\'s next show at my cinemas, soonest first', () {
    final soon = data.nextAtMyCinemas();
    expect(soon.first.wallClock.hour, 19);
    expect(startsIn(soon.first.startsAt.difference(data.now)), 'بعد 45 دقيقة');
    expect(soon.every((s) => s.cinemaId == 'scene:cfc'), isTrue);
  });

  test('times read in Cairo wall clock', () {
    final late = catalog.showtimes.last;
    expect(clock(late.wallClock), '12:30');
    expect(period(late.wallClock), 'ص');
  });

  testWidgets('home shows the sections with real showtimes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AppScope(
              data: data,
              child: HomeScreen(onSearch: () {}),
            ),
          ),
        ),
      ),
    );
    expect(find.text('الجاي في سينماتك'), findsOneWidget);
    expect(find.text('Clayface'), findsWidgets);
  });
}
