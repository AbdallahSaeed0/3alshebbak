import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_data.dart';
import '../data/prefs.dart';
import '../data/tickets.dart';
import '../services/location.dart';
import '../services/push.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/common.dart';
import 'following_screen.dart';
import 'onboarding_screen.dart';
import 'tickets_screen.dart';

/// Which cinemas Home shows: mine, or every cinema in one city.
Future<void> showCityPicker(BuildContext context) {
  final data = AppScope.of(context);
  final current = data.prefs.homeCity;
  void pick(String? city) {
    data.prefs.setHomeCity(city);
    Navigator.of(context).pop();
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              tr('الرئيسية تعرض…', 'Home shows…'),
              style: AppText.display(22),
            ),
          ),
          _Choice(
            label: tr('سينماتي', 'My cinemas'),
            detail: cinemaCount(data.prefs.myCinemas.length),
            icon: Icons.star,
            selected: current == null,
            onTap: () => pick(null),
          ),
          Divider(color: AppColors.hairline, indent: 20, endIndent: 20),
          for (final (city, count) in data.cities)
            _Choice(
              label: cityName(city),
              detail: cinemaCount(count),
              icon: Icons.location_city,
              selected: current == city,
              onTap: () => pick(city),
            ),
        ],
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.detail,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: selected ? AppColors.gold : AppColors.muted),
      title: Text(
        label,
        style: AppText.body(
          15,
          weight: FontWeight.w700,
          color: selected ? AppColors.gold : AppColors.text,
        ),
      ),
      subtitle: Text(detail, style: AppText.body(12, color: AppColors.muted)),
      trailing: selected ? Icon(Icons.check, color: AppColors.gold) : null,
    );
  }
}

/// The fourth tab: my films and tickets, then my cinemas, location,
/// notifications, and where the data comes from.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onExplore});

  /// Switches to the Explore tab (from an empty Following page).
  final VoidCallback onExplore;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _locating = false;
  bool _enablingPush = false;

  void _say(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppText.body(13)),
        action: action,
      ),
    );
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final problem = await refreshSpot(AppScope.of(context).prefs);
    if (!mounted) return;
    setState(() => _locating = false);
    if (problem == null)
      return _say(tr('تمام، حدّثنا مكانك', 'Done, location updated'));
    _say(
      describe(problem),
      action:
          problem == LocationProblem.deniedForever ||
              problem == LocationProblem.serviceOff
          ? SnackBarAction(
              label: tr('الإعدادات', 'Settings'),
              onPressed: () => openFixFor(problem),
            )
          : null,
    );
  }

  Future<void> _enablePush() async {
    setState(() => _enablingPush = true);
    final on = await Push.instance.enable();
    if (!mounted) return;
    setState(() => _enablingPush = false);
    _say(
      on
          ? tr(
              'هنقولك أول ما تذاكر الأفلام اللي بتتابعها تنزل',
              'We\'ll tell you when tickets for films you follow go on sale',
            )
          : tr(
              'الإشعارات مقفولة. تقدر تفتحها من إعدادات الموبايل.',
              'Notifications are off. You can turn them on in your phone\'s settings.',
            ),
    );
  }

  void _openFollowing() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(backgroundColor: AppColors.background),
          body: FollowingScreen(
            onExplore: () {
              Navigator.of(context).pop();
              widget.onExplore();
            },
          ),
        ),
      ),
    );
  }

  void _redoSetup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            OnboardingScreen(onDone: () => Navigator.of(context).pop()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final prefs = data.prefs;
    final spot = prefs.spot;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('الإعدادات', 'Settings'), style: AppText.display(24)),
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: barSpace(context)),
        children: [
          _Heading(tr('حاجاتي', 'Mine')),
          _Group(
            children: [
              _Row(
                icon: Icons.notifications_none,
                title: tr('متابعاتي', 'Following'),
                detail: prefs.following.isEmpty
                    ? tr(
                        'الأفلام اللي بتستناها، ونقولك أول ما تذاكرها تنزل',
                        'Films you\'re waiting for; we tell you when tickets go on sale',
                      )
                    : tr(
                        '${prefs.following.length} فيلم بتتابعه',
                        'Following ${prefs.following.length} films',
                      ),
                onTap: _openFollowing,
              ),
              FutureBuilder<TicketStore>(
                future: TicketStore.load(),
                builder: (context, snap) => ListenableBuilder(
                  listenable: snap.data ?? Listenable.merge(const []),
                  builder: (context, _) => _Row(
                    icon: Icons.confirmation_number_outlined,
                    title: tr('تذاكري', 'My tickets'),
                    detail: switch (snap.data?.all.length) {
                      null || 0 => tr(
                        'اسكرينات تذاكرك، محفوظة على موبايلك',
                        'Screenshots of your tickets, kept on your phone',
                      ),
                      final n => tr('$n تذكرة محفوظة', '$n tickets saved'),
                    },
                    onTap: () => openTickets(context),
                  ),
                ),
              ),
            ],
          ),
          _Heading(tr('الشكل واللغة', 'Look & language')),
          _Group(
            children: [
              _Choices<Appearance>(
                icon: Icons.contrast,
                title: tr('الشكل', 'Appearance'),
                value: prefs.appearance,
                options: {
                  Appearance.system: tr('زي الموبايل', 'Phone'),
                  Appearance.light: tr('فاتح', 'Light'),
                  Appearance.dark: tr('غامق', 'Dark'),
                },
                onChanged: prefs.setAppearance,
              ),
              _Choices<bool>(
                icon: Icons.translate,
                title: tr('اللغة', 'Language'),
                value: prefs.english,
                // Each language named in itself, so either reader finds theirs.
                options: const {false: 'العربية', true: 'English'},
                onChanged: prefs.setEnglish,
              ),
            ],
          ),
          _Heading(tr('سينماتي', 'My cinemas')),
          _Group(
            children: [
              _Row(
                icon: Icons.star_outline,
                title: tr('اختار سينماتك من جديد', 'Pick your cinemas again'),
                detail: tr(
                  'متختار ${cinemaCount(prefs.myCinemas.length)} · نبدأ من اللوكيشن',
                  '${cinemaCount(prefs.myCinemas.length)} picked · starts from your location',
                ),
                onTap: _redoSetup,
              ),
              _Row(
                icon: Icons.location_city_outlined,
                title: tr('الرئيسية تعرض', 'Home shows'),
                detail: switch (prefs.homeCity) {
                  null => tr('سينماتي', 'My cinemas'),
                  final city => tr(
                    'كل سينمات ${cityName(city)}',
                    'All ${cityName(city)} cinemas',
                  ),
                },
                onTap: () => showCityPicker(context),
              ),
            ],
          ),
          _Heading(tr('الموقع', 'Location')),
          _Group(
            children: [
              _Row(
                icon: Icons.my_location,
                title: spot == null
                    ? tr('استخدم موقعي', 'Use my location')
                    : tr('حدّث موقعي', 'Update my location'),
                detail: spot == null
                    ? tr(
                        'عشان نرتب السينمات من الأقرب ليك',
                        'To sort cinemas nearest first',
                      )
                    : tr(
                        'محفوظ على الموبايل بس، مش بيتبعت لحد',
                        'Kept on your phone only, never sent anywhere',
                      ),
                trailing: _locating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _locating ? null : _locate,
              ),
              if (spot != null)
                _Row(
                  icon: Icons.location_off_outlined,
                  title: tr('امسح موقعي', 'Forget my location'),
                  onTap: () {
                    prefs.clearSpot();
                    _say(tr('مسحنا مكانك', 'Location forgotten'));
                  },
                ),
            ],
          ),
          _Heading(tr('الإشعارات', 'Notifications')),
          _Group(
            children: [
              if (Push.available)
                _Row(
                  icon: Icons.notifications_active_outlined,
                  title: tr(
                    'شغّل إشعارات "التذاكر نزلت"',
                    'Turn on "tickets are out" alerts',
                  ),
                  detail: tr(
                    'للأفلام اللي بتتابعها · ${prefs.following.length} فيلم دلوقتي',
                    'For films you follow · ${prefs.following.length} now',
                  ),
                  trailing: _enablingPush
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _enablingPush ? null : _enablePush,
                )
              else
                _Row(
                  icon: Icons.notifications_off_outlined,
                  title: tr(
                    'الإشعارات في تطبيق أندرويد',
                    'Notifications are in the Android app',
                  ),
                  detail: tr(
                    'النسخة دي مش بتبعت إشعارات',
                    'This version doesn\'t send notifications',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Group(
            children: [
              _Row(
                icon: Icons.privacy_tip_outlined,
                title: tr('سياسة الخصوصية', 'Privacy policy'),
                onTap: () => launchUrl(
                  Uri.parse(
                    'https://abdallahsaeed0.github.io/3alshebbak/privacy.html'
                    '${Lang.english ? '#en' : ''}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A setting with a few choices, as a row of segments.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
    child: Row(
      children: [
        Icon(icon, color: AppColors.muted),
        const SizedBox(width: 16),
        Text(title, style: AppText.body(15, weight: FontWeight.w600)),
        const SizedBox(width: 12),
        Expanded(
          child: SegmentedButton<T>(
            segments: [
              for (final e in options.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppColors.gold,
              selectedForegroundColor: AppColors.onGold,
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.muted,
              side: BorderSide(color: AppColors.hairline),
              textStyle: AppText.body(12.5, weight: FontWeight.w700),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
        ),
      ],
    ),
  );
}

/// One section's rows on a single card, iOS-style.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: AppDecor.card(radius: 18),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 56, color: AppColors.hairline),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
    child: Text(
      text,
      style: AppText.body(13, weight: FontWeight.w700, color: AppColors.gold),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: AppColors.muted),
    title: Text(title, style: AppText.body(15, weight: FontWeight.w600)),
    subtitle: detail == null
        ? null
        : Text(detail!, style: AppText.body(12, color: AppColors.muted)),
    trailing:
        trailing ??
        (onTap != null
            ? Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: AppColors.muted,
              )
            : null),
  );
}
