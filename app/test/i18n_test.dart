import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/models.dart';
import 'package:shebbak/util/format.dart';
import 'package:shebbak/util/i18n.dart';

void main() {
  tearDown(() => Lang.english = false);

  test('Arabic by default', () {
    expect(tr('النهارده', 'Today'), 'النهارده');
    expect(dayLabel('2026-11-01'), 'الأحد 1 نوفمبر');
    expect(cinemaCount(3), '3 سينمات');
    expect(distance(3.24), '3.2 كم');
    expect(startsIn(const Duration(minutes: 90)), 'بعد ساعة ونص');
    expect(cityName('Cairo'), 'القاهرة');
  });

  test('English when picked', () {
    Lang.english = true;
    expect(tr('النهارده', 'Today'), 'Today');
    expect(dayLabel('2026-11-01'), 'Sun 1 Nov');
    expect(cinemaCount(1), '1 cinema');
    expect(cinemaCount(3), '3 cinemas');
    expect(distance(0.43), '400 m');
    expect(startsIn(const Duration(minutes: 75)), 'in 1 h 15 min');
    expect(period(DateTime(2026, 11, 1, 19)), 'PM');
    expect(shortFormat('Standard'), 'Standard');
    expect(cityName('Cairo'), 'Cairo');
  });

  test('Arabic area names still find cinemas in English', () {
    Lang.english = true;
    expect(areaNameAr('Maadi'), 'المعادي');
  });

  test('in English an Egyptian film shows its English title', () {
    const m = Movie(
      id: 'tmdb:1651563',
      tmdbId: 1651563,
      title: 'Family Wanted',
      titleAr: 'مطلوب عائليا',
      originalTitle: 'مطلوب عائليا',
    );
    expect(m.displayTitle, 'مطلوب عائليا');
    Lang.english = true;
    expect(m.displayTitle, 'Family Wanted');
  });
}
