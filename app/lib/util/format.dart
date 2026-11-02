// Wording for times, days, counts and distances, in Egyptian Arabic or
// English (see i18n.dart).

import 'i18n.dart';

const _days = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];
const _daysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];
const _monthsEn = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "7:30" on a 12-hour clock (Cairo wall time).
String clock(DateTime wall) {
  final h = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
  return '$h:${wall.minute.toString().padLeft(2, '0')}';
}

/// "ص" / "م", "AM" / "PM".
String period(DateTime wall) => wall.hour < 12 ? tr('ص', 'AM') : tr('م', 'PM');

/// "الأحد 1 نوفمبر" / "Sun 1 Nov" from "2026-11-01".
String dayLabel(String isoDate) {
  final d = DateTime.parse(isoDate);
  return Lang.english
      ? '${_daysEn[d.weekday - 1]} ${d.day} ${_monthsEn[d.month - 1]}'
      : '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// "بعد 45 دقيقة", "بعد ساعة و15 د", "بعد ساعتين"; "in 45 min", "in 1 h 15 min".
String startsIn(Duration d) {
  final mins = d.inMinutes;
  if (Lang.english) {
    if (mins < 1) return 'starting now';
    if (mins < 60) return 'in $mins min';
    final h = mins ~/ 60, m = mins % 60;
    return m == 0 ? 'in $h h' : 'in $h h $m min';
  }
  if (mins < 1) return 'بيبدأ دلوقتي';
  if (mins < 60) return 'بعد $mins دقيقة';
  final h = mins ~/ 60;
  final m = mins % 60;
  final hours = switch (h) {
    1 => 'ساعة',
    2 => 'ساعتين',
    _ => '$h ساعات',
  };
  if (m == 0) return 'بعد $hours';
  if (m == 30) return 'بعد $hours ونص';
  return 'بعد $hours و$m د';
}

/// A chain's format name shortened for a chip: "2D · PREMIUM" → "PREMIUM",
/// "Standard" / "Regular" → "عادي" ("Standard").
String shortFormat(String format) {
  final last = format.split('·').last.trim();
  return switch (last.toLowerCase()) {
    'standard' ||
    'regular' ||
    '2d' ||
    'standard & deluxe' => tr('عادي', 'Standard'),
    _ => last,
  };
}

/// "1 سينما" / "3 سينمات"; "1 cinema" / "3 cinemas".
String cinemaCount(int n) => Lang.english
    ? (n == 1 ? '1 cinema' : '$n cinemas')
    : (n >= 3 && n <= 10 ? '$n سينمات' : '$n سينما');

/// Joins place parts ("Nasr City", "2.9 كم"). In Arabic the right-to-left
/// mark before each separator keeps a number after a Latin name from joining
/// the Latin run, which would print "كم Nasr City · 2.9".
String joinPlace(Iterable<String> parts) =>
    parts.join(Lang.english ? ' · ' : '‏ · ');

/// Kept short: "800 م", "3.2 كم", "45 كم"; "800 m", "3.2 km".
String distance(double km) {
  final m = tr('م', 'm'), k = tr('كم', 'km');
  if (km < 1) return '${(km * 1000).round() ~/ 50 * 50} $m';
  if (km < 10) return '${km.toStringAsFixed(1)} $k';
  return '${km.round()} $k';
}

const _cities = {
  'Cairo': 'القاهرة',
  'Alexandria': 'إسكندرية',
  'Mansoura': 'المنصورة',
  'Tanta': 'طنطا',
  'Zagazig': 'الزقازيق',
  'Banha': 'بنها',
  'Shebin El Kom': 'شبين الكوم',
  'Menofia': 'المنوفية',
  'Fayoum': 'الفيوم',
  'Minya': 'المنيا',
  'Sohag': 'سوهاج',
  'Luxor': 'الأقصر',
  'Hurghada': 'الغردقة',
  'Sharm El Sheikh': 'شرم الشيخ',
  'Ismailia': 'الإسماعيلية',
  'Suez': 'السويس',
  'Ain Sokhna': 'العين السخنة',
  'Port Said': 'بورسعيد',
  'Marsa Matrouh': 'مرسى مطروح',
};

/// The city in the app's language (Arabic when we have it).
String cityName(String city) => Lang.english ? city : cityNameAr(city);

/// The city in Arabic, whatever the app's language (for search).
String cityNameAr(String city) => _cities[city] ?? city;

const _areas = {
  '6th of October': '6 أكتوبر',
  'Agamy': 'العجمي',
  'Ain Shams': 'عين شمس',
  'Ain Sokhna': 'العين السخنة',
  'Corniche': 'الكورنيش',
  'Dokki': 'الدقي',
  'Downtown': 'وسط البلد',
  'El Gouna': 'الجونة',
  'Garden City': 'جاردن سيتي',
  'Haram': 'الهرم',
  'Heliopolis': 'مصر الجديدة',
  'Maadi': 'المعادي',
  'Madinaty': 'مدينتي',
  'Manial': 'المنيل',
  'Moharam Bek': 'محرم بك',
  'Montazah': 'المنتزه',
  'Nasr City': 'مدينة نصر',
  'New Cairo': 'التجمع',
  'New Sohag': 'سوهاج الجديدة',
  'Obour City': 'العبور',
  'Port Tawfik': 'بور توفيق',
  'Rehab City': 'الرحاب',
  'Roshdy': 'رشدي',
  'San Stefano': 'سان ستيفانو',
  'Shebin El Kom': 'شبين الكوم',
  'Sheikh Zayed': 'الشيخ زايد',
  'Smouha': 'سموحة',
  'Zamalek': 'الزمالك',
};

/// The area in the app's language (Arabic when we have it).
String areaName(String area) => Lang.english ? area : areaNameAr(area);

/// The area in Arabic, whatever the app's language (for search).
String areaNameAr(String area) => _areas[area] ?? area;
