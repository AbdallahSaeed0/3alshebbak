import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/halls.dart';
import 'package:shebbak/data/models.dart';

Showtime _show(String format, {String at = 'elcinema:americana-plaza'}) =>
    Showtime(
      cinemaId: at,
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

  test('VOX: IMAX, 4DX and MAX find their halls; MAX VIP and Gold don\'t', () {
    const almaza = 'elcinema:city-centre-almaza';
    const moe = 'elcinema:mall-of-egypt';
    const alex = 'elcinema:city-centre-alexandria';
    final imax = halls.forShowtime(_show('IMAX', at: almaza))!;
    expect(imax.seats.length, 311);
    // VOX letters rows from the back: Q is nearest the screen.
    expect(imax.rowNames.first, 'Q');
    expect(imax.rowNames.last, 'A');
    expect(halls.forShowtime(_show('4DX', at: almaza))!.seats.length, 60);
    expect(halls.forShowtime(_show('4DX', at: moe))!.seats.length, 84);
    // MAX shows find the MAX hall checked 14-18 Nov; IMAX and MAX VIP don't
    expect(halls.forShowtime(_show('MAX', at: almaza))!.name, 'MAX 3');
    expect(halls.forShowtime(_show('MAX', at: moe))!.seats.length, 221);
    expect(halls.forShowtime(_show('MAX', at: alex))!.seats.length, 301);
    expect(halls.forShowtime(_show('IMAX', at: almaza))!.name, 'IMAX');
    for (final at in [almaza, moe, alex]) {
      expect(halls.forShowtime(_show('MAX VIP', at: at)), isNull, reason: at);
    }
    expect(halls.forShowtime(_show('Gold', at: almaza)), isNull);
    // Almaza has one Kids hall in use; Mall of Egypt two different ones
    expect(halls.forShowtime(_show('Kids', at: almaza))!.seats.length, 69);
    expect(halls.forShowtime(_show('Kids', at: moe)), isNull);
  });

  test('Renaissance: Madinaty VIP is matched; Banha has two, so neither', () {
    final mad = halls.forShowtime(_show('VIP', at: 'renaissance:madinty'))!;
    expect(mad.seats.length, 56);
    expect(mad.rowNames.first, 'A');
    expect(halls.forShowtime(_show('VIP', at: 'renaissance:banha')), isNull);
    expect(
      halls.forShowtime(_show('Regular', at: 'renaissance:madinty')),
      isNull,
    );
  });

  test('Galaxy El Maadi: the Dine-in hall', () {
    const at = 'elcinema:galaxy-el-maadi';
    final hall = halls.forShowtime(_show('Dine-in · Dine-In', at: at))!;
    expect(hall.seats.length, 40);
    expect(
      halls.forShowtime(_show('VIP · Standard', at: at))!.seats.length,
      81,
    );
    expect(halls.forShowtime(_show('Standard', at: at)), isNull);
    // Sun City's VIP halls differ (VIP2 has a row more than VIP3)
    expect(
      halls.forShowtime(_show('VIP · Standard', at: 'elcinema:sun-city')),
      isNull,
    );
  });

  test('Zamalek is one hall: Standard is the stalls, the balcony waits', () {
    const at = 'elcinema:zamalek-cinema';
    expect(halls.forShowtime(_show('Standard', at: at))!.seats.length, 302);
    expect(halls.forShowtime(_show('Balcon', at: at)), isNull);
    // multi-hall cinemas recorded from elCinema stay unmatched
    for (final c in [
      'elcinema:el-tahrir-cinema',
      'elcinema:grand-hurghada-cinema',
    ]) {
      expect(halls.forShowtime(_show('Standard', at: c)), isNull, reason: c);
    }
  });

  test('a show that names its hall gets that hall, whatever its format', () {
    Showtime at(String cinema, String hall, [String format = 'Standard']) =>
        Showtime(
          cinemaId: cinema,
          movieId: 'tmdb:1',
          businessDate: '2026-11-15',
          startsAt: DateTime.utc(2026, 11, 15, 10),
          wallClock: DateTime(2026, 11, 15, 12),
          format: format,
          hall: hall,
        );
    const tahrir = 'elcinema:el-tahrir-cinema';
    expect(halls.forShowtime(at(tahrir, 'elcinema:1340001'))!.name, 'Screen 1');
    expect(halls.forShowtime(at(tahrir, 'elcinema:1340007'))!.name, 'screen 5');
    // a hall whose plan isn't recorded: nothing, rather than a guess
    expect(halls.forShowtime(at(tahrir, 'elcinema:1349999')), isNull);
    // one hall sold as two screens
    const galaxy = 'elcinema:galaxy-el-maadi';
    expect(
      halls.forShowtime(at(galaxy, 'elcinema:1290003', 'VIP · Standard'))!.name,
      'VIP',
    );
    expect(halls.forShowtime(at(galaxy, 'elcinema:1290005'))!.name, 'Screen 4');
    expect(
      halls.forShowtime(at('elcinema:sun-city', 'elcinema:1100002'))!.name,
      'VIP2',
    );
    final zawya = halls.forShowtime(at('elcinema:zawya', 'elcinema:1050206'))!;
    expect(zawya.name, 'Karim 1');
    expect(zawya.freeSeating, isTrue);
  });

  test('Renaissance shows find their hall by screen id', () {
    Showtime at(String cinema, String hall, String format) => Showtime(
      cinemaId: cinema,
      movieId: 'tmdb:1',
      businessDate: '2026-11-15',
      startsAt: DateTime.utc(2026, 11, 15, 8),
      wallClock: DateTime(2026, 11, 15, 10),
      format: format,
      hall: hall,
    );
    final rehab = halls.forShowtime(
      at('renaissance:al_rehab', 'rns:7fdc72', 'Regular'),
    )!;
    expect(rehab.seats.length, 246);
    expect(rehab.rowNames[1], 'L'); // nearest the screen, after a gap
    final vip = halls.forShowtime(
      at('renaissance:banha', 'rns:271672', 'VIP'),
    )!;
    expect(vip.seats.length, 28);
    // without a hall, Banha's VIP stays unknown (two VIP halls)
    expect(halls.forShowtime(_show('VIP', at: 'renaissance:banha')), isNull);
  });

  test('Premiere: shows by hall id, special halls by format', () {
    Showtime at(String cinema, String hall) => Showtime(
      cinemaId: cinema,
      movieId: 'tmdb:1',
      businessDate: '2026-11-14',
      startsAt: DateTime.utc(2026, 11, 14, 21),
      wallClock: DateTime(2026, 11, 14, 23),
      format: 'Standard',
      hall: hall,
    );
    final p90 = halls.forShowtime(at('elcinema:premiere-point90', 'prm:4:14'))!;
    expect(p90.name, 'Screen 3');
    expect(p90.seats.length, 225);
    expect(
      halls.forShowtime(at('premiere:nile-cinema', 'prm:1:2'))!.name,
      'Screen 2',
    );
    // Point90's MX4D, Arkan's MAX and its Plus hall (elCinema calls it VIP)
    expect(
      halls
          .forShowtime(_show('MX4D · 4DX', at: 'elcinema:premiere-point90'))!
          .seats
          .length,
      80,
    );
    expect(
      halls.forShowtime(_show('MAX', at: 'elcinema:cima-arkan'))!.name,
      'MAX Cima',
    );
    expect(
      halls.forShowtime(_show('VIP · VIP', at: 'elcinema:cima-arkan'))!.name,
      'Plus Cima',
    );
    // an ordinary show without its hall gets none
    expect(
      halls.forShowtime(_show('Standard', at: 'premiere:nile-cinema')),
      isNull,
    );
  });

  test('formats match part by part, whole, 2D/3D aside', () {
    expect(Halls.formatParts('MX4D · 4DX'), {'MX4D', '4DX'});
    expect(Halls.formatParts('2D · IMAX'), {'IMAX'});
    expect(Halls.formatParts('IMAX 3D · Infinity Vision'), {
      'IMAX',
      'INFINITY VISION',
    });
    expect(Halls.formatParts('MAX VIP'), {'MAX VIP'});
    const am = 'elcinema:americana-plaza';
    expect(halls.forShowtime(_show('MX4D · 4DX', at: am))!.name, 'SCREEN MX4D');
    expect(halls.forShowtime(_show('IMAX 3D', at: am))!.name, 'Screen IMAX');
  });

  test('Scene: District 5 IMAX, CFC 4DX and ScreenX', () {
    final imax = halls.forShowtime(_show('IMAX', at: 'scene:district5'))!;
    expect(imax.seats.length, 249);
    expect(imax.rowNames.first, 'A'); // Scene draws its plan turned 180°
    expect(halls.forShowtime(_show('4DX', at: 'scene:cfc'))!.seats.length, 60);
    expect(
      halls.forShowtime(_show('ScreenX', at: 'scene:cfc'))!.seats.length,
      390,
    );
    expect(halls.forShowtime(_show('Standard', at: 'scene:cfc')), isNull);
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
