import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/catalog_cache.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('catalog'));
  tearDown(() => dir.delete(recursive: true));

  test('keeps the last catalog for the next launch', () async {
    final cache = CatalogCache.at(File('${dir.path}/c.json'));
    expect(await cache.read(), isNull);
    await cache.write(['[]', '[]', '[{"a":1}]']);
    expect(await cache.read(), ['[]', '[]', '[{"a":1}]']);
  });

  test('a catalog older than two days is not opened on', () async {
    final cache = CatalogCache.at(File('${dir.path}/c.json'));
    final saved = DateTime(2026, 11, 1, 20);
    await cache.write(['[]'], now: saved);
    expect(await cache.read(now: saved.add(const Duration(days: 1))), ['[]']);
    expect(await cache.read(now: saved.add(const Duration(days: 3))), isNull);
  });

  test('a damaged file is ignored', () async {
    final file = File('${dir.path}/c.json')..writeAsStringSync('{not json');
    expect(await CatalogCache.at(file).read(), isNull);
  });
}
