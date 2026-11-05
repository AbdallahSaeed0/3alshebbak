import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/widgets/background_help.dart';

void main() {
  test('Xiaomi phones get the autostart, battery and lock steps', () {
    final steps = stepsFor('Xiaomi');
    expect(makerName('xiaomi'), isNotNull);
    expect(steps.map((s) => s.open), contains('openAutostart'));
    expect(steps.map((s) => s.open), contains('openBattery'));
    expect(steps.length, 4);
  });

  test('unknown phones still get battery and notification steps', () {
    expect(makerName('google'), isNull);
    expect(stepsFor('google').length, 2);
    for (final brand in ['oppo', 'realme', 'samsung', 'vivo', 'honor']) {
      expect(makerName(brand), isNotNull, reason: brand);
      expect(stepsFor(brand).every((s) => s.title.isNotEmpty), isTrue);
    }
  });
}
