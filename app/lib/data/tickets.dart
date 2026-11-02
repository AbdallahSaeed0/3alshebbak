import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A screenshot of a booking, kept on this phone only — there are no
/// accounts, so deleting the app deletes them.
class Ticket {
  const Ticket({required this.id, required this.addedAt, this.movieId});

  final String id;
  final DateTime addedAt;

  /// The film it's for, when the user said.
  final String? movieId;

  Map<String, Object?> toJson() => {
    'id': id,
    'addedAt': addedAt.toIso8601String(),
    'movieId': movieId,
  };

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
    id: j['id'] as String,
    addedAt: DateTime.parse(j['addedAt'] as String),
    movieId: j['movieId'] as String?,
  );
}

/// My tickets: the list in shared preferences, each image in the app's own
/// folder. On the web there's no folder, so images go into browser storage
/// too, which holds only a few MB — fine for trying the app out.
class TicketStore extends ChangeNotifier {
  TicketStore._(this._store, this._dir, this._tickets);

  static const _listKey = 'tickets';
  static String _imageKey(String id) => 'ticket_image_$id';

  static Future<TicketStore>? _loading;

  /// Loaded once, on first use.
  static Future<TicketStore> load() => _loading ??= _load();

  static Future<TicketStore> _load() async {
    final store = await SharedPreferences.getInstance();
    Directory? dir;
    if (!kIsWeb) {
      dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/tickets',
      );
      await dir.create(recursive: true);
    }
    return open(store, dir);
  }

  /// Reads the list from [store]; images live in [dir], or in [store] when
  /// it's null (the web).
  @visibleForTesting
  static TicketStore open(SharedPreferences store, Directory? dir) {
    final raw = store.getString(_listKey);
    final tickets = raw == null
        ? <Ticket>[]
        : [
            for (final j in jsonDecode(raw) as List)
              Ticket.fromJson(j as Map<String, dynamic>),
          ];
    return TicketStore._(store, dir, tickets);
  }

  final SharedPreferences _store;
  final Directory? _dir;
  final List<Ticket> _tickets;
  final _webImages = <String, Uint8List>{};

  /// Newest first.
  List<Ticket> get all =>
      [..._tickets]..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  File _file(String id) => File('${_dir!.path}/$id.jpg');

  ImageProvider image(Ticket t) {
    if (_dir != null) return FileImage(_file(t.id));
    final bytes = _webImages[t.id] ??= base64Decode(
      _store.getString(_imageKey(t.id)) ?? '',
    );
    return MemoryImage(bytes);
  }

  /// The image's path on the phone, for sharing. Null on the web.
  String? path(Ticket t) => _dir == null ? null : _file(t.id).path;

  Future<void> add(Uint8List bytes, {String? movieId}) async {
    final ticket = Ticket(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      addedAt: DateTime.now(),
      movieId: movieId,
    );
    if (_dir != null) {
      await _file(ticket.id).writeAsBytes(bytes, flush: true);
    } else {
      // Throws when browser storage is full; the screen says so.
      await _store.setString(_imageKey(ticket.id), base64Encode(bytes));
      _webImages[ticket.id] = bytes;
    }
    _tickets.add(ticket);
    await _saveList();
  }

  Future<void> remove(Ticket ticket) async {
    _tickets.removeWhere((t) => t.id == ticket.id);
    if (_dir != null) {
      final file = _file(ticket.id);
      if (await file.exists()) await file.delete();
    } else {
      await _store.remove(_imageKey(ticket.id));
      _webImages.remove(ticket.id);
    }
    await _saveList();
  }

  Future<void> _saveList() async {
    await _store.setString(
      _listKey,
      jsonEncode([for (final t in _tickets) t.toJson()]),
    );
    notifyListeners();
  }
}
