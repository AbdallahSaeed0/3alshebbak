import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import '../util/i18n.dart';

const _seenKey = 'tour_seen';

/// The things the tour points at, tagged where they're built (Home's header,
/// the tab bar). A step whose target isn't on screen shows in the middle.
abstract final class TourTargets {
  static final city = GlobalKey(debugLabel: 'tour city');
  static final search = GlobalKey(debugLabel: 'tour search');
  static final bell = GlobalKey(debugLabel: 'tour bell');
  static final assistant = GlobalKey(debugLabel: 'tour assistant');
  static final _tabs = [
    for (var i = 0; i < 4; i++) GlobalKey(debugLabel: 'tour tab $i'),
  ];
  static GlobalKey tab(int i) => _tabs[i];

  /// Set by the shell: switches to Home, where the tour's targets are.
  static VoidCallback? showHome;
}

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

Future<void> showTour(BuildContext context) async {
  TourTargets.showHome?.call();
  // Let Home and the bar settle before measuring where things are.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => const _Tour(),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

typedef _Step = ({GlobalKey? target, String title, String body});

List<_Step> get _steps => [
  (
    target: TourTargets.city,
    title: tr('سينماتك', 'Your cinemas'),
    body: tr(
      'الرئيسية بتعرض اللي جاي في سينماتك. من هنا تختار سينماتك أو مدينة كاملة.',
      'Home shows what\'s next at your cinemas. Pick your cinemas or a whole city here.',
    ),
  ),
  (
    target: TourTargets.search,
    title: tr('دوّر واحجز', 'Search and book'),
    body: tr(
      'دوّر على أي فيلم أو سينما. ودوس على أي ميعاد: هتطلعلك تذكرة فيها زرار الحجز، وتقدر تبعتها لصحابك.',
      'Find any film or cinema. Tap any time for a ticket with the booking button, and send it to friends.',
    ),
  ),
  (
    target: TourTargets.bell,
    title: tr('الإشعارات', 'Notifications'),
    body: tr(
      'كل الجديد للأفلام اللي بتتابعها: الحجز اللي فتح والمواعيد الجديدة، وتفاصيل كل واحد.',
      'Everything new for films you follow: booking opening and new showtimes, with the details.',
    ),
  ),
  (
    target: TourTargets.tab(1),
    title: tr('استكشف وتابع', 'Explore and follow'),
    body: tr(
      'كل الأفلام المعروضة واللي جاية قريب. من صفحة أي فيلم دوس «تابع الفيلم» ويوصلك إشعار أول ما الحجز يفتح.',
      'Every film showing and coming soon. On a film\'s page tap "Follow" to hear when booking opens.',
    ),
  ),
  (
    target: TourTargets.assistant,
    title: tr('اسأل عالشباك', 'Ask 3al Shebbak'),
    body: tr(
      'اختار مدينة وفيلم ويقولك مواعيده، أو يدلّك على أقرب سينما ليك.',
      'Pick a city and a film for its times, or find your nearest cinema.',
    ),
  ),
  (
    target: TourTargets.tab(2),
    title: tr('السينمات', 'Cinemas'),
    body: tr(
      'كل سينمات مصر على الخريطة. علّم على سينماتك بالنجمة.',
      'Every cinema in Egypt on a map. Star the ones you go to.',
    ),
  ),
  (
    target: TourTargets.tab(3),
    title: tr('الإعدادات', 'Settings'),
    body: tr(
      'الإشعارات واللغة والشكل، وتبعتلنا رأيك أو شكوى، وتعيد الجولة دي.',
      'Notifications, language and look, send us feedback, and replay this tour.',
    ),
  ),
];

class _Tour extends StatefulWidget {
  const _Tour();

  @override
  State<_Tour> createState() => _TourState();
}

class _TourState extends State<_Tour> {
  int _step = 0;

  /// Where [key]'s widget is on screen, if it's showing.
  Rect? _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    return screen.overlaps(rect) ? rect : null;
  }

  void _next() {
    if (_step == _steps.length - 1) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final step = steps[_step];
    final last = _step == steps.length - 1;
    final size = MediaQuery.sizeOf(context);
    final hole = _rectOf(step.target)?.inflate(6);
    // The note goes below a target in the top half, above one lower down.
    final below = hole == null || hole.center.dy < size.height / 2;

    final card = Material(
      color: AppColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(step.title, style: AppText.display(20))),
                Text(
                  '${_step + 1}/${steps.length}',
                  style: AppText.body(12, color: AppColors.muted),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Text(step.body, style: AppText.body(14)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!last)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      tr('تخطي', 'Skip'),
                      style: AppText.body(13, color: AppColors.muted),
                    ),
                  ),
                FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.onGold,
                    textStyle: AppText.body(14, weight: FontWeight.w700),
                  ),
                  child: Text(
                    last ? tr('يلا بينا', 'Let\'s go') : tr('التالي', 'Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _next,
      child: Stack(
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<Rect?>(
              tween: RectTween(end: hole),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (_, r, _) =>
                  CustomPaint(painter: _Spotlight(r, AppColors.gold)),
            ),
          ),
          if (hole == null)
            Center(
              child: Padding(padding: const EdgeInsets.all(16), child: card),
            )
          else
            Positioned(
              left: 16,
              right: 16,
              top: below ? hole.bottom + 14 : null,
              bottom: below ? null : size.height - hole.top + 14,
              child: card,
            ),
        ],
      ),
    );
  }
}

/// The screen dimmed, with a lit, outlined hole around what's being shown.
class _Spotlight extends CustomPainter {
  _Spotlight(this.hole, this.edge);

  final Rect? hole;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(dim, Paint()..color = const Color(0xB3000000));
      return;
    }
    final lit = RRect.fromRectAndRadius(h, const Radius.circular(18));
    canvas.drawPath(
      Path.combine(PathOperation.difference, dim, Path()..addRRect(lit)),
      Paint()..color = const Color(0xB3000000),
    );
    canvas.drawRRect(
      lit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_Spotlight old) => old.hole != hole;
}
