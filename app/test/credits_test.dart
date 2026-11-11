import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/models.dart';

void main() {
  test('credits read the short keys the pipeline writes', () {
    final c = Credits.fromJson({
      'cast': [
        {'n': 'Ahmed Ezz', 'c': 'Omar', 'p': '/a.jpg'},
        {'n': 'Mona Zaki', 'c': null, 'p': null},
        {'c': 'no name'},
      ],
      'dir': ['Tarek Al Eryan'],
    })!;
    expect(c.cast.map((p) => p.name), ['Ahmed Ezz', 'Mona Zaki']);
    expect(c.cast.first.photoUrl, 'https://image.tmdb.org/t/p/w185/a.jpg');
    expect(c.cast[1].photoUrl, isNull);
    expect(c.directors, ['Tarek Al Eryan']);
  });

  test('no credits, or not credits, is null', () {
    expect(Credits.fromJson(null), isNull);
    expect(Credits.fromJson('x'), isNull);
    expect(Credits.fromJson({'cast': [], 'dir': []}), isNull);
  });

  test('a movie row from the database carries its credits', () {
    final m = Movie.fromJson({
      'id': 'tmdb:1',
      'title': 'X',
      'credits': {
        'cast': [
          {'n': 'A'},
        ],
        'dir': [],
      },
    });
    expect(m.credits?.cast.single.name, 'A');
  });
}
