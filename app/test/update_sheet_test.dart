import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/services/app_version.dart';
import 'package:shebbak/widgets/update_sheet.dart';

void main() {
  test('release notes keep the bullets, drop markdown', () {
    expect(
      releaseNotes(
        '## عالشباك 0.2.4\n\n**الجديد:**\n- 🔔 **إشعار التحديث:** بقى أوضح\n- 💬 حاجة تانية\n\nالتثبيت',
      ),
      ['🔔 إشعار التحديث: بقى أوضح', '💬 حاجة تانية'],
    );
    expect(releaseNotes(null), isEmpty);
  });

  testWidgets(
    'the update sheet shows the versions, the notes and a download button',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: UpdateSheet(
                current: '0.2.3',
                update: (
                  version: '0.2.4',
                  download: Uri.parse('https://example.com/a.apk'),
                  notes: ['🔔 إشعار التحديث بقى أوضح'],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('فيه نسخة جديدة! 🎉'), findsOneWidget);
      expect(find.textContaining('0.2.4'), findsOneWidget);
      expect(find.text('🔔 إشعار التحديث بقى أوضح'), findsOneWidget);
      expect(find.text('نزّلها دلوقتي'), findsOneWidget);
    },
  );
}
