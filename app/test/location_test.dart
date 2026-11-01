import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/app_data.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/data/prefs.dart';
import 'package:shebbak/data/repository.dart';
import 'package:shebbak/util/format.dart';

void main() {
  const cfc = Cinema(
    id: 'scene:cfc',
    chain: 'Scene',
    name: 'Cairo Festival City',
    lat: 30.0281,
    lng: 31.4077,
  );
  const almaza = Cinema(
    id: 'elcinema:city-centre-almaza',
    chain: 'VOX',
    name: 'City Centre Almaza',
    lat: 30.0855,
    lng: 31.3711,
  );
  const alex = Cinema(
    id: 'elcinema:city-centre-alexandria',
    chain: 'VOX',
    name: 'City Centre Alexandria',
    lat: 31.1667,
    lng: 29.9333,
  );
  const unpinned = Cinema(id: 'x:nowhere', chain: 'Independent', name: 'X');

  AppData dataAt(Spot? spot) => AppData(
    CatalogData(
      cinemas: {for (final c in [alex, unpinned, almaza, cfc]) c.id: c},
      movies: const {},
      showtimes: const [],
    ),
    Prefs.memory(spot: spot),
  );

  test('Cairo to Alexandria is about 180 km as the crow flies', () {
    final km = haversineKm(30.0444, 31.2357, 31.2001, 29.9187);
    expect(km, closeTo(180, 5));
  });

  test('cinemas sort nearest first, unpinned ones last', () {
    // Standing in New Cairo, a few hundred metres from Festival City.
    final data = dataAt((lat: 30.03, lng: 31.41));
    expect(
      data.byDistance(data.prefs.spot!).map((c) => c.id),
      [cfc.id, almaza.id, alex.id, unpinned.id],
    );
    expect(distance(data.distanceKm(cfc)!), '300 م');
  });

  test('no distance without a location', () {
    expect(dataAt(null).distanceKm(cfc), isNull);
  });

  test('distances read short', () {
    expect(distance(0.42), '400 م');
    expect(distance(3.24), '3.2 كم');
    expect(distance(45.6), '46 كم');
  });
}
