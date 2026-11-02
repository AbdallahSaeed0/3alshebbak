import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_data.dart';
import '../data/tickets.dart';
import '../services/location.dart';
import '../services/push.dart';
import '../theme.dart';
import '../util/format.dart';
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
            child: Text('الرئيسية تعرض…', style: AppText.display(22)),
          ),
          _Choice(
            label: 'سينماتي',
            detail: cinemaCount(data.prefs.myCinemas.length),
            icon: Icons.star,
            selected: current == null,
            onTap: () => pick(null),
          ),
          const Divider(color: AppColors.hairline, indent: 20, endIndent: 20),
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
      trailing: selected
          ? const Icon(Icons.check, color: AppColors.gold)
          : null,
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
    if (problem == null) return _say('تمام، حدّثنا مكانك');
    _say(
      describe(problem),
      action:
          problem == LocationProblem.deniedForever ||
              problem == LocationProblem.serviceOff
          ? SnackBarAction(
              label: 'الإعدادات',
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
          ? 'هنقولك أول ما تذاكر الأفلام اللي بتتابعها تنزل'
          : 'الإشعارات مقفولة. تقدر تفتحها من إعدادات الموبايل.',
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
        title: Text('الإعدادات', style: AppText.display(24)),
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Heading('حاجاتي'),
          _Row(
            icon: Icons.notifications_none,
            title: 'متابعاتي',
            detail: prefs.following.isEmpty
                ? 'الأفلام اللي بتستناها، ونقولك أول ما تذاكرها تنزل'
                : '${prefs.following.length} فيلم بتتابعه',
            onTap: _openFollowing,
          ),
          FutureBuilder<TicketStore>(
            future: TicketStore.load(),
            builder: (context, snap) => ListenableBuilder(
              listenable: snap.data ?? Listenable.merge(const []),
              builder: (context, _) => _Row(
                icon: Icons.confirmation_number_outlined,
                title: 'تذاكري',
                detail: switch (snap.data?.all.length) {
                  null || 0 => 'اسكرينات تذاكرك، محفوظة على موبايلك',
                  final n => '$n تذكرة محفوظة',
                },
                onTap: () => openTickets(context),
              ),
            ),
          ),
          const _Heading('سينماتي'),
          _Row(
            icon: Icons.star_outline,
            title: 'اختار سينماتك من جديد',
            detail:
                'متختار ${cinemaCount(prefs.myCinemas.length)} · نبدأ من اللوكيشن',
            onTap: _redoSetup,
          ),
          _Row(
            icon: Icons.location_city_outlined,
            title: 'الرئيسية تعرض',
            detail: switch (prefs.homeCity) {
              null => 'سينماتي',
              final city => 'كل سينمات ${cityName(city)}',
            },
            onTap: () => showCityPicker(context),
          ),
          const _Heading('الموقع'),
          _Row(
            icon: Icons.my_location,
            title: spot == null ? 'استخدم موقعي' : 'حدّث موقعي',
            detail: spot == null
                ? 'عشان نرتب السينمات من الأقرب ليك'
                : 'محفوظ على الموبايل بس، مش بيتبعت لحد',
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
              title: 'امسح موقعي',
              onTap: () {
                prefs.clearSpot();
                _say('مسحنا مكانك');
              },
            ),
          const _Heading('الإشعارات'),
          if (Push.available)
            _Row(
              icon: Icons.notifications_active_outlined,
              title: 'شغّل إشعارات "التذاكر نزلت"',
              detail:
                  'للأفلام اللي بتتابعها · ${prefs.following.length} فيلم دلوقتي',
              trailing: _enablingPush
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _enablingPush ? null : _enablePush,
            )
          else
            const _Row(
              icon: Icons.notifications_off_outlined,
              title: 'الإشعارات في تطبيق أندرويد',
              detail: 'النسخة دي مش بتبعت إشعارات',
            ),
          const _Heading('عن التطبيق'),
          _Row(
            icon: Icons.theaters_outlined,
            title: 'مواعيد الحفلات',
            detail:
                'من مواقع السينمات نفسها، ومن elCinema.com للباقي · بتتحدث كل نص ساعة',
            onTap: () => launchUrl(Uri.parse('https://elcinema.com')),
          ),
          _Row(
            icon: Icons.movie_outlined,
            title: 'بيانات الأفلام والبوسترات',
            detail:
                'This product uses the TMDB API but is not endorsed or certified by TMDB.',
            onTap: () => launchUrl(Uri.parse('https://www.themoviedb.org')),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
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
            ? const Icon(Icons.chevron_left, color: AppColors.muted)
            : null),
  );
}
