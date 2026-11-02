import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/app_data.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/util/search.dart';

void main() {
  test('Arabic spelling variants and diacritics match', () {
    expect(SearchQuery('افاتار').matches(['أفاتار: النار والرماد']), isTrue);
    expect(SearchQuery('مدرسه').matches(['مَدْرَسَة الروابي']), isTrue);
    expect(SearchQuery('مستشفي').matches(['مستشفى']), isTrue);
  });

  test('English ignores case, punctuation and spaces', () {
    expect(
      SearchQuery('spiderman').matches(['Spider-Man: Brand New Day']),
      isTrue,
    );
    expect(
      SearchQuery('BRAND new').matches(['Spider-Man: Brand New Day']),
      isTrue,
    );
  });

  test('every word must match, in any order and across fields', () {
    final q = SearchQuery('new day spider');
    expect(q.matches(['Spider-Man: Brand New Day']), isTrue);
    expect(SearchQuery('spider batman').matches(['Spider-Man']), isFalse);
    expect(
      SearchQuery('سيتي ستارز').matches(['City Stars', 'سيتي ستارز']),
      isTrue,
    );
  });

  test('an empty query matches everything', () {
    expect(SearchQuery('  ').matches(['anything']), isTrue);
  });

  group('display title', () {
    test('a foreign film shows its English title, Arabic underneath', () {
      const m = Movie(
        id: 'tmdb:1',
        tmdbId: 1,
        title: 'Avatar: Fire and Ash',
        titleAr: 'أفاتار: النار والرماد',
      );
      expect(m.displayTitle, 'Avatar: Fire and Ash');
      expect(m.subtitle, 'أفاتار: النار والرماد');
    });

    test('an Egyptian film shows its Arabic title, English underneath', () {
      const m = Movie(
        id: 'tmdb:2',
        tmdbId: 2,
        title: 'Welad Rizk 3',
        originalTitle: 'ولاد رزق 3',
      );
      expect(m.displayTitle, 'ولاد رزق 3');
      expect(m.subtitle, 'Welad Rizk 3');
    });

    test('a Kurdish film is not Arabic, though its script looks it', () {
      const m = Movie(
        id: 'tmdb:3',
        tmdbId: 3,
        title: 'No Paradise If You Are Killed by a Woman',
        originalTitle: 'بەهەشت نابینیت ئەگەر ژن بتکوژێت',
      );
      expect(m.displayTitle, 'No Paradise If You Are Killed by a Woman');
    });

    test('a film TMDB does not know keeps the chain\'s Arabic title', () {
      const m = Movie(id: 'local:x', title: 'Belkis', titleAr: 'بلقيس');
      expect(m.displayTitle, 'بلقيس');
    });
  });

  test('cinemas match by Arabic area and city names', () {
    const c = Cinema(
      id: 'elcinema:galaxy-el-maadi',
      chain: 'Galaxy',
      name: 'Galaxy El Maadi',
      city: 'Cairo',
      area: 'Maadi',
    );
    expect(AppData.cinemaMatches(c, SearchQuery('المعادى')), isTrue);
    expect(AppData.cinemaMatches(c, SearchQuery('القاهرة galaxy')), isTrue);
    expect(AppData.cinemaMatches(c, SearchQuery('الزمالك')), isFalse);
  });
}
