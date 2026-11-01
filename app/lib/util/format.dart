// Egyptian-Arabic wording for times, days and formats.

const _days = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];
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

/// "7:30" on a 12-hour clock (Cairo wall time).
String clock(DateTime wall) {
  final h = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
  return '$h:${wall.minute.toString().padLeft(2, '0')}';
}

/// "ص" / "م".
String period(DateTime wall) => wall.hour < 12 ? 'ص' : 'م';

/// "الأحد 1 نوفمبر" from "2026-11-01".
String dayLabel(String isoDate) {
  final d = DateTime.parse(isoDate);
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// "بعد 45 دقيقة", "بعد ساعة و15 د", "بعد ساعتين".
String startsIn(Duration d) {
  final mins = d.inMinutes;
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
/// "Standard" / "Regular" → "عادي".
String shortFormat(String format) {
  final last = format.split('·').last.trim();
  return switch (last.toLowerCase()) {
    'standard' || 'regular' || '2d' || 'standard & deluxe' => 'عادي',
    _ => last,
  };
}

/// "1 سينما" / "2 سينما" / "3 سينمات".
String cinemaCount(int n) => n >= 3 && n <= 10 ? '$n سينمات' : '$n سينما';
