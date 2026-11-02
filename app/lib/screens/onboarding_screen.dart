import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../services/location.dart';
import '../services/push.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/ticket_mark.dart';
import '../util/i18n.dart';

/// First open: welcome → where are you (to sort cinemas by distance) → pick
/// your cinemas → turn on "tickets are out" notifications (when push is set
/// up). Everything can be skipped; skipping keeps the default cinemas.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, location, cinemas, notifications }

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.welcome;
  bool _locating = false;
  LocationProblem? _problem;
  final Set<String> _picked = {};

  List<_Step> get _steps => [
    _Step.welcome,
    _Step.location,
    _Step.cinemas,
    if (Push.available) _Step.notifications,
  ];

  void _next() {
    final i = _steps.indexOf(_step);
    if (i + 1 < _steps.length) {
      setState(() => _step = _steps[i + 1]);
    } else {
      _finish();
    }
  }

  void _finish() {
    final prefs = AppScope.of(context).prefs;
    if (_picked.isNotEmpty) prefs.setCinemas(_picked);
    prefs.finishOnboarding();
    widget.onDone();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _problem = null;
    });
    final (spot, problem) = await locateOnce();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _problem = problem;
    });
    if (spot == null) return;
    final data = AppScope.of(context);
    data.prefs.setSpot(spot);
    // The nearest few become "my cinemas" to start with: everything within
    // 12 km, at least the closest one, at most four.
    final near = data.byDistance(spot);
    _picked
      ..clear()
      ..addAll([
        for (final (i, c) in near.indexed)
          if (i == 0 || (i < 4 && (data.distanceKm(c) ?? 99) <= 12)) c.id,
      ]);
    _next();
  }

  Future<void> _enablePush() async {
    await Push.instance.enable();
    if (mounted) _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  _Progress(count: _steps.length, at: _steps.indexOf(_step)),
                  const Spacer(),
                  if (_step != _Step.cinemas)
                    TextButton(
                      onPressed: _step == _Step.welcome ? _finish : _next,
                      child: Text(
                        _step == _Step.welcome
                            ? tr('تخطي', 'Skip')
                            : tr('بعدين', 'Later'),
                        style: AppText.body(14, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    _Step.welcome => _Welcome(onStart: _next),
                    _Step.location => _Location(
                      locating: _locating,
                      problem: _problem,
                      onLocate: _locate,
                      onManual: _next,
                    ),
                    _Step.cinemas => _PickCinemas(
                      picked: _picked,
                      onToggle: (id) => setState(() {
                        if (!_picked.remove(id)) _picked.add(id);
                      }),
                      onDone: _next,
                    ),
                    _Step.notifications => _Notifications(
                      onEnable: _enablePush,
                      onLater: _finish,
                    ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marquee bulbs, the lit ones are the steps done so far.
class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.at});
  final int count;
  final int at;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('خطوة ${at + 1} من $count', 'Step ${at + 1} of $count'),
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: i == at ? 22 : 7,
              height: 7,
              margin: EdgeInsetsDirectional.only(end: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i <= at ? AppColors.gold : AppColors.perforation,
                boxShadow: i <= at
                    ? [BoxShadow(color: AppColors.gold, blurRadius: 6)]
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Big centered message with one main action and an optional quiet one.
class _Page extends StatelessWidget {
  const _Page({
    required this.art,
    required this.title,
    required this.body,
    required this.primary,
    this.secondary,
    this.note,
  });

  final Widget art;
  final String title;
  final String body;
  final Widget primary;
  final Widget? secondary;
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(child: art),
          const SizedBox(height: 28),
          Text(title, textAlign: TextAlign.center, style: AppText.display(34)),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppText.body(15, color: AppColors.muted),
          ),
          if (note != null) ...[const SizedBox(height: 16), note!],
          const Spacer(),
          primary,
          if (secondary != null) ...[const SizedBox(height: 8), secondary!],
        ],
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.onGold,
        disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: busy
          ? SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.onGold,
              ),
            )
          : Text(label, style: AppText.display(20, color: AppColors.onGold)),
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(
        label,
        style: AppText.body(15, color: AppColors.text, weight: FontWeight.w600),
      ),
    );
  }
}

/// A round badge with the step's icon, lit like a marquee.
class _Badge extends StatelessWidget {
  const _Badge(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: AppColors.gold, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.25),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, size: 48, color: AppColors.gold),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    return _Page(
      art: const TicketMark(size: 150),
      title: tr('أهلاً بيك عالشباك', 'Welcome to 3al Shebbak'),
      body: tr(
        'مواعيد ${cinemaCount(data.catalog.cinemas.length)} في مصر في مكان واحد، '
            'وأول ما تذاكر فيلم مستنيه تنزل، نقولك.',
        'Showtimes for ${cinemaCount(data.catalog.cinemas.length)} in Egypt in one place, '
            "and the moment tickets for a film you're waiting on go on sale, we tell you.",
      ),
      primary: _GoldButton(
        label: tr('يلا بينا', 'Let\'s go'),
        onPressed: onStart,
      ),
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({
    required this.locating,
    required this.problem,
    required this.onLocate,
    required this.onManual,
  });

  final bool locating;
  final LocationProblem? problem;
  final VoidCallback onLocate;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final p = problem;
    final needsSettings =
        p == LocationProblem.deniedForever || p == LocationProblem.serviceOff;
    return _Page(
      art: const _Badge(Icons.near_me_outlined),
      title: tr('فين أقرب سينما ليك؟', 'Where\'s your nearest cinema?'),
      body: tr(
        'هنستخدم مكانك عشان نرتبلك السينمات من الأقرب للأبعد. '
            'مكانك بيفضل على موبايلك، مش بنبعته لحد.',
        'We use your location to sort cinemas from nearest to farthest. '
            'It stays on your phone; we never send it anywhere.',
      ),
      note: p == null
          ? null
          : Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber),
              ),
              child: Column(
                children: [
                  Text(
                    describe(p),
                    textAlign: TextAlign.center,
                    style: AppText.body(13),
                  ),
                  if (needsSettings)
                    TextButton(
                      onPressed: () => openFixFor(p),
                      child: Text(
                        tr('افتح الإعدادات', 'Open settings'),
                        style: AppText.body(
                          13,
                          color: AppColors.gold,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
      primary: _GoldButton(
        label: p == null
            ? tr('استخدم موقعي', 'Use my location')
            : tr('جرّب تاني', 'Try again'),
        busy: locating,
        onPressed: onLocate,
      ),
      secondary: _QuietButton(
        label: tr('هختار بنفسي', 'I\'ll choose myself'),
        onPressed: onManual,
      ),
    );
  }
}

class _PickCinemas extends StatefulWidget {
  const _PickCinemas({
    required this.picked,
    required this.onToggle,
    required this.onDone,
  });

  final Set<String> picked;
  final ValueChanged<String> onToggle;
  final VoidCallback onDone;

  @override
  State<_PickCinemas> createState() => _PickCinemasState();
}

class _PickCinemasState extends State<_PickCinemas> {
  /// Without a location: one city at a time, Cairo first.
  String _city = 'Cairo';

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final spot = data.prefs.spot;
    final List<Cinema> list;
    List<String> cities = const [];
    if (spot != null) {
      list = data.byDistance(spot);
    } else {
      final count = <String, int>{};
      for (final c in data.catalog.cinemas.values) {
        if (c.city != null) count[c.city!] = (count[c.city!] ?? 0) + 1;
      }
      cities = count.keys.toList()
        ..sort((a, b) => count[b]!.compareTo(count[a]!));
      list = data.catalog.cinemas.values.where((c) => c.city == _city).toList()
        ..sort((a, b) => a.label.compareTo(b.label));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Text(
            tr('سينماتك', 'your cinemas'),
            style: AppText.display(32),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            spot != null
                ? tr(
                    'رتبناها من الأقرب ليك، واخترنالك الأقرب. غيّر براحتك.',
                    'Sorted nearest first, with the closest picked for you. Change them as you like.',
                  )
                : tr(
                    'اختار السينمات اللي بتروحها، عشان نوريك مواعيدها الأول.',
                    'Pick the cinemas you go to, so we show their times first.',
                  ),
            style: AppText.body(13, color: AppColors.muted),
          ),
        ),
        if (cities.isNotEmpty)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              children: [
                for (final city in cities)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: _CityPill(
                      label: cityName(city),
                      selected: city == _city,
                      onTap: () => setState(() => _city = city),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final c = list[i];
              final km = data.distanceKm(c);
              final picked = widget.picked.contains(c.id);
              final place = joinPlace([
                if (c.area != null) c.area!,
                if (spot != null && c.city != null) cityName(c.city!),
              ]);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Material(
                  color: picked ? AppColors.raised : AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: picked ? AppColors.gold : AppColors.hairline,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => widget.onToggle(c.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            picked ? Icons.check_circle : Icons.circle_outlined,
                            color: picked ? AppColors.gold : AppColors.muted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.label,
                                  style: AppText.body(
                                    15,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                if (place.isNotEmpty)
                                  Text(
                                    place,
                                    style: AppText.body(
                                      12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (km != null)
                            Text(
                              distance(km),
                              style: AppText.body(
                                13,
                                color: AppColors.gold,
                                weight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _GoldButton(
            label: widget.picked.isEmpty
                ? tr('بعدين', 'Later')
                : tr(
                    'تمام (${cinemaCount(widget.picked.length)})',
                    'Done (${cinemaCount(widget.picked.length)})',
                  ),
            onPressed: widget.onDone,
          ),
        ),
      ],
    );
  }
}

class _CityPill extends StatelessWidget {
  const _CityPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.gold : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppColors.gold : AppColors.hairline),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: AppText.body(
                13,
                color: selected ? AppColors.onGold : AppColors.text,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notifications extends StatelessWidget {
  const _Notifications({required this.onEnable, required this.onLater});
  final VoidCallback onEnable;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return _Page(
      art: const _Badge(Icons.notifications_active_outlined),
      title: tr(
        'نقولك أول ما التذاكر تنزل؟',
        'Tell you when tickets go on sale?',
      ),
      body: tr(
        'تابع أي فيلم، وأول ما سينما من سينماتك تفتح الحجز ليه هيوصلك إشعار. '
            'مرة واحدة في اليوم بالكتير لكل فيلم.',
        'Follow any film, and when one of your cinemas opens booking for it '
            'you get a notification. At most once a day per film.',
      ),
      primary: _GoldButton(
        label: tr('أيوه، بلغني', 'Yes, notify me'),
        onPressed: onEnable,
      ),
      secondary: _QuietButton(
        label: tr('مش دلوقتي', 'Not now'),
        onPressed: onLater,
      ),
    );
  }
}
