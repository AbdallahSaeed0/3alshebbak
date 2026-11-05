import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../util/i18n.dart';

const _device = MethodChannel('shebbak/device');

Future<bool> _open(String method) async {
  try {
    return await _device.invokeMethod<bool>(method) ?? false;
  } catch (_) {
    return false;
  }
}

/// Step-by-step help for phones that kill apps in the background (Xiaomi,
/// Oppo, Samsung…), so alerts arrive. The steps follow the phone's maker,
/// and each one that has a settings screen gets a button straight to it.
Future<void> showBackgroundHelp(BuildContext context) async {
  String brand = '';
  try {
    brand = await _device.invokeMethod<String>('brand') ?? '';
  } catch (_) {}
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        _BackgroundHelp(steps: stepsFor(brand), maker: makerName(brand)),
  );
}

typedef HelpStep = ({String title, String body, String? button, String? open});

String? makerName(String brand) => switch (_family(brand)) {
  'xiaomi' => tr('شاومي', 'Xiaomi'),
  'oppo' => tr('أوبو / ريلمي / وان بلس', 'Oppo / Realme / OnePlus'),
  'samsung' => tr('سامسونج', 'Samsung'),
  'vivo' => tr('فيفو', 'Vivo'),
  'huawei' => tr('هواوي / أونر', 'Huawei / Honor'),
  _ => null,
};

String _family(String brand) {
  final b = brand.toLowerCase();
  if (b.contains('xiaomi') || b.contains('redmi') || b.contains('poco')) {
    return 'xiaomi';
  }
  if (b.contains('oppo') || b.contains('realme') || b.contains('oneplus')) {
    return 'oppo';
  }
  if (b.contains('samsung')) return 'samsung';
  if (b.contains('vivo') || b.contains('iqoo')) return 'vivo';
  if (b.contains('huawei') || b.contains('honor')) return 'huawei';
  return '';
}

HelpStep get _notificationsStep => (
  title: tr('اتأكد إن الإشعارات شغالة', 'Check notifications are on'),
  body: tr(
    'في صفحة التطبيق دوس "الإشعارات" وخلّي "السماح بالإشعارات" شغال.',
    'On the app\'s page tap "Notifications" and keep "Allow notifications" on.',
  ),
  button: tr('افتح صفحة التطبيق', 'Open app info'),
  open: 'openAppDetails',
);

List<HelpStep> stepsFor(String brand) => switch (_family(brand)) {
  'xiaomi' => [
    (
      title: tr('شغّل "التشغيل التلقائي"', 'Turn on "Autostart"'),
      body: tr(
        'دوس الزرار، هتلاقي لستة تطبيقات. دوّر على عالشباك وشغّل المفتاح اللي جنبه.',
        'Tap the button to get a list of apps. Find 3al Shebbak and turn its switch on.',
      ),
      button: tr('افتح التشغيل التلقائي', 'Open Autostart'),
      open: 'openAutostart',
    ),
    (
      title: tr('خلّي البطارية "بلا قيود"', 'Set battery to "No restrictions"'),
      body: tr(
        'دوس الزرار، واختار "بلا قيود" (No restrictions). '
            'لو فتحلك صفحة التطبيق: دوس "توفير البطارية" واختارها من هناك.',
        'Tap the button and pick "No restrictions". If it opens the app\'s '
            'page instead, tap "Battery saver" and pick it there.',
      ),
      button: tr('افتح توفير البطارية', 'Open battery saver'),
      open: 'openBattery',
    ),
    (
      title: tr('اقفل التطبيق في الأحدث', 'Lock the app in recents'),
      body: tr(
        'افتح التطبيقات الأخيرة (المربع اللي تحت)، دوس دوسة طويلة على عالشباك، '
            'واختار علامة القفل 🔒 عشان "مسح الكل" مايقفلوش.',
        'Open recent apps (the square button), long-press 3al Shebbak and tap '
            'the lock 🔒 so "Clear all" doesn\'t close it.',
      ),
      button: null,
      open: null,
    ),
    _notificationsStep,
  ],
  'oppo' => [
    (
      title: tr('اسمح بالتشغيل التلقائي', 'Allow auto launch'),
      body: tr(
        'دوس الزرار ودوّر على عالشباك وشغّل "التشغيل التلقائي" (Auto launch).',
        'Tap the button, find 3al Shebbak and turn on "Auto launch".',
      ),
      button: tr('افتح التشغيل التلقائي', 'Open auto launch'),
      open: 'openAutostart',
    ),
    (
      title: tr('اسمح بالعمل في الخلفية', 'Allow background activity'),
      body: tr(
        'في صفحة التطبيق دوس "استخدام البطارية" وشغّل "السماح بالنشاط في الخلفية".',
        'On the app\'s page tap "Battery usage" and turn on "Allow background activity".',
      ),
      button: tr('افتح صفحة التطبيق', 'Open app info'),
      open: 'openAppDetails',
    ),
    _notificationsStep,
  ],
  'samsung' => [
    (
      title: tr('خلّي البطارية "غير مقيّد"', 'Set battery to "Unrestricted"'),
      body: tr(
        'في صفحة التطبيق دوس "البطارية" واختار "غير مقيّد" (Unrestricted).',
        'On the app\'s page tap "Battery" and pick "Unrestricted".',
      ),
      button: tr('افتح صفحة التطبيق', 'Open app info'),
      open: 'openAppDetails',
    ),
    (
      title: tr('شيله من التطبيقات النايمة', 'Take it out of sleeping apps'),
      body: tr(
        'الإعدادات ← العناية بالجهاز ← البطارية ← حدود استخدام الخلفية: '
            'اتأكد إن عالشباك مش في "التطبيقات النائمة".',
        'Settings → Device care → Battery → Background usage limits: make '
            'sure 3al Shebbak isn\'t in "Sleeping apps".',
      ),
      button: null,
      open: null,
    ),
    _notificationsStep,
  ],
  'vivo' || 'huawei' => [
    (
      title: tr('اسمح بالتشغيل في الخلفية', 'Allow running in background'),
      body: tr(
        'دوس الزرار ودوّر على عالشباك وشغّل المفتاح اللي جنبه '
            '(التشغيل التلقائي / التشغيل في الخلفية).',
        'Tap the button, find 3al Shebbak and turn its switch on '
            '(Autostart / background start).',
      ),
      button: tr('افتح الإعداد', 'Open the setting'),
      open: 'openAutostart',
    ),
    (
      title: tr('البطارية بدون قيود', 'Battery without limits'),
      body: tr(
        'في صفحة التطبيق دوس "البطارية" واختار السماح بالعمل في الخلفية / بدون قيود.',
        'On the app\'s page tap "Battery" and allow background use / no limits.',
      ),
      button: tr('افتح صفحة التطبيق', 'Open app info'),
      open: 'openAppDetails',
    ),
    _notificationsStep,
  ],
  _ => [
    (
      title: tr('خلّي البطارية بدون قيود', 'Set battery to unrestricted'),
      body: tr(
        'في صفحة التطبيق دوس "البطارية" واختار "غير مقيّد" أو "بدون قيود".',
        'On the app\'s page tap "Battery" and pick "Unrestricted".',
      ),
      button: tr('افتح صفحة التطبيق', 'Open app info'),
      open: 'openAppDetails',
    ),
    _notificationsStep,
  ],
};

class _BackgroundHelp extends StatelessWidget {
  const _BackgroundHelp({required this.steps, required this.maker});
  final List<HelpStep> steps;
  final String? maker;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr('عشان الإشعارات توصلك', 'So alerts reach you'),
              style: AppText.display(26),
            ),
            const SizedBox(height: 6),
            Text(
              maker != null
                  ? tr(
                      'تليفونك $maker، وده بيقفل التطبيقات في الخلفية عشان يوفر بطارية. اعمل الخطوات دي مرة واحدة بس:',
                      'Your phone is $maker, which closes apps in the background to save battery. Do these steps once:',
                    )
                  : tr(
                      'بعض التليفونات بتقفل التطبيقات في الخلفية عشان توفر بطارية. اعمل الخطوات دي مرة واحدة بس:',
                      'Some phones close apps in the background to save battery. Do these steps once:',
                    ),
              style: AppText.body(14, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            for (final (i, s) in steps.indexed) _Step(number: i + 1, step: s),
            const SizedBox(height: 8),
            Text(
              tr(
                'أسامي الإعدادات ممكن تختلف شوية حسب نسخة التليفون.',
                'Setting names can differ a little between phone versions.',
              ),
              textAlign: TextAlign.center,
              style: AppText.body(12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.step});
  final int number;
  final HelpStep step;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.raised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold,
          ),
          child: Text(
            '$number',
            style: AppText.numerals(17, color: AppColors.onGold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: AppText.body(15, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(step.body, style: AppText.body(13, color: AppColors.muted)),
              if (step.button != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _open(step.open!),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(step.button!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: BorderSide(color: AppColors.goldEdge),
                    textStyle: AppText.body(13, weight: FontWeight.w700),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
