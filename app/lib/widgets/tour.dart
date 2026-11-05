import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import '../util/i18n.dart';

const _seenKey = 'tour_seen';

/// The quick tour, once: after onboarding, or after updating to the version
/// that has it. Settings can replay it with [showTour].
Future<void> showTourOnce(BuildContext context) async {
  try {
    final store = await SharedPreferences.getInstance();
    if (store.getBool(_seenKey) ?? false) return;
    await store.setBool(_seenKey, true);
  } catch (_) {
    return;
  }
  if (context.mounted) await showTour(context);
}

Future<void> showTour(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _Tour(),
);

typedef _Slide = ({IconData icon, String title, String body});

List<_Slide> get _slides => [
  (
    icon: Icons.home_rounded,
    title: tr('الرئيسية', 'Home'),
    body: tr(
      'الجاي في سينماتك، والأفلام اللي حجزها لسه نازل، وكل حفلات النهارده. '
          'غيّر المدينة من الزرار اللي فوق.',
      'What\'s next at your cinemas, films just on sale, and all of today\'s '
          'shows. Switch city from the button at the top.',
    ),
  ),
  (
    icon: Icons.confirmation_number_outlined,
    title: tr('دوس على أي ميعاد', 'Tap any time'),
    body: tr(
      'هتطلعلك تذكرة فيها السينما والقاعة، وزرار يوديك تحجز على موقع السينما على طول.',
      'You get a ticket with the cinema and hall, and a button straight to '
          'the cinema\'s booking page.',
    ),
  ),
  (
    icon: Icons.notifications_active_outlined,
    title: tr('تابع الفيلم', 'Follow a film'),
    body: tr(
      'من صفحة الفيلم دوس "تابع الفيلم"، وأول ما الحجز يفتح أو تنزل مواعيد جديدة هيوصلك إشعار.',
      'Tap "Follow" on a film\'s page, and you\'ll be notified when booking '
          'opens or new showtimes come out.',
    ),
  ),
  (
    icon: Icons.forum_outlined,
    title: tr('اسأل عالشباك', 'Ask 3al Shebbak'),
    body: tr(
      'الزرار اللي جنب السيرش: اختار المدينة والفيلم وهيقولك المواعيد، أو أقرب سينما ليك.',
      'The button next to search: pick a city and a film for its times, or '
          'find your nearest cinema.',
    ),
  ),
  (
    icon: Icons.groups_outlined,
    title: tr('نروح سوا؟', 'Shall we go?'),
    body: tr(
      'علّم على كام ميعاد وابعتهم لصحابك صورة شكلها حلو، يختاروا منها.',
      'Tick a few times and send them to friends as a nice picture to pick from.',
    ),
  ),
];

class _Tour extends StatefulWidget {
  const _Tour();

  @override
  State<_Tour> createState() => _TourState();
}

class _TourState extends State<_Tour> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    final last = _page == slides.length - 1;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  tr('جولة سريعة', 'Quick tour'),
                  style: AppText.body(
                    13,
                    weight: FontWeight.w700,
                    color: AppColors.gold,
                  ),
                ),
                const Spacer(),
                if (!last)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      tr('تخطي', 'Skip'),
                      style: AppText.body(13, color: AppColors.muted),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 250,
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final s in slides)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.raised,
                            border: Border.all(color: AppColors.goldEdge),
                          ),
                          child: Icon(s.icon, size: 38, color: AppColors.gold),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: AppText.display(26),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.body,
                          textAlign: TextAlign.center,
                          style: AppText.body(14, color: AppColors.muted),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? AppColors.gold : AppColors.hairline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => last
                  ? Navigator.of(context).pop()
                  : _pages.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.onGold,
                minimumSize: const Size.fromHeight(50),
                textStyle: AppText.body(15, weight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                last ? tr('يلا بينا', 'Let\'s go') : tr('التالي', 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
