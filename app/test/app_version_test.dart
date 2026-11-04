import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/services/app_version.dart';

void main() {
  test('a release is newer only when a version part is higher', () {
    expect(isNewer('0.2.0', '0.1.1'), isTrue);
    expect(isNewer('0.1.10', '0.1.9'), isTrue);
    expect(isNewer('1.0', '0.9.9'), isTrue);
    expect(isNewer('0.1.1', '0.1.1'), isFalse);
    expect(isNewer('0.1.1', '0.2.0'), isFalse);
    expect(isNewer('0.2.0+5', '0.2.0'), isFalse);
  });
}
