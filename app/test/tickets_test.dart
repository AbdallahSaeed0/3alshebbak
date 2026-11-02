import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shebbak/data/tickets.dart';

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('tickets');
  });
  tearDown(() => dir.delete(recursive: true));

  test('a ticket is kept as a file and survives reopening', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = TicketStore.open(prefs, dir);
    await store.add(Uint8List.fromList([1, 2, 3]), movieId: 'tmdb:1');

    final again = TicketStore.open(prefs, dir);
    expect(again.all.single.movieId, 'tmdb:1');
    expect(File(again.path(again.all.single)!).readAsBytesSync(), [1, 2, 3]);
  });

  test('removing a ticket deletes its file', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = TicketStore.open(prefs, dir);
    await store.add(Uint8List.fromList([9]));
    final ticket = store.all.single;
    final path = store.path(ticket)!;

    await store.remove(ticket);
    expect(store.all, isEmpty);
    expect(File(path).existsSync(), isFalse);
    expect(TicketStore.open(prefs, dir).all, isEmpty);
  });

  test('without a folder (the web) the image goes into preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = TicketStore.open(prefs, null);
    await store.add(Uint8List.fromList([4, 5]));
    expect(store.path(store.all.single), isNull);
    expect(
      prefs.getKeys().where((k) => k.startsWith('ticket_image_')),
      hasLength(1),
    );
  });

  test('newest ticket first', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = TicketStore.open(prefs, dir);
    await store.add(Uint8List.fromList([1]), movieId: 'old');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.add(Uint8List.fromList([2]), movieId: 'new');
    expect(store.all.map((t) => t.movieId), ['new', 'old']);
  });

  test('a used ticket moves to the used list, and back', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = TicketStore.open(prefs, dir);
    await store.add(Uint8List.fromList([1]), movieId: 'tmdb:1');
    final ticket = store.all.single;
    expect(store.active, hasLength(1));

    await store.setUsed(ticket, true);
    expect(store.active, isEmpty);
    expect(store.used.single.movieId, 'tmdb:1');
    // Kept across reopening.
    expect(TicketStore.open(prefs, dir).used, hasLength(1));

    await store.setUsed(store.used.single, false);
    expect(store.used, isEmpty);
    expect(store.active, hasLength(1));
  });
}
