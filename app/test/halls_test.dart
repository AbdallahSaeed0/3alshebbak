import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/halls.dart';
import 'package:shebbak/data/models.dart';

Showtime _show(String format) => Showtime(
  cinemaId: 'elcinema:americana-plaza',
  movieId: 'tmdb:1',
  businessDate: '2026-11-12',
  startsAt: DateTime.utc(2026, 11, 12, 16, 45),
  wallClock: DateTime(2026, 11, 12, 18, 45),
  format: format,
);

void main() {
  final halls = Halls.fromJson(
    jsonDecode(File('assets/halls/halls.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test('a show finds its hall by format; ordinary halls stay unknown', () {
    expect(halls.forShowtime(_show('IMAX'))!.name, 'Screen IMAX');
    expect(halls.forShowtime(_show('MX4D'))!.name, 'SCREEN MX4D');
    expect(halls.forShowtime(_show('Standard')), isNull);
  });

  test('the IMAX layout is read seat for seat', () {
    final imax = halls.forShowtime(_show('IMAX'))!;
    expect(imax.seats.length, 455);
    expect(imax.rowNames.first, 'A');
    expect(imax.seats.where((s) => s.row == 'K').length, 12); // cross aisle
  });

  test('the best seat is central and away from the front', () {
    for (final format in ['IMAX', 'MX4D']) {
      final hall = halls.forShowtime(_show(format))!;
      final best = hall.bestSeat;
      final view = hall.viewFrom(best);
      expect(view.sideAngle, lessThan(5), reason: format);
      expect(best.depth, greaterThan(0), reason: format);
      final front = hall.seats.firstWhere((s) => s.depth == 0);
      expect(hall.viewFrom(front).score, lessThan(view.score), reason: format);
    }
  });
}
