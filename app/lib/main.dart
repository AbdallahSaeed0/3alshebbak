import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/app_data.dart';
import 'data/prefs.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';
import 'screens/film_screen.dart';
import 'screens/news_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'services/background_refresh.dart';
import 'services/home_widget_sync.dart';
import 'services/premiere_live.dart';
import 'services/push.dart';
import 'services/usage.dart';
import 'services/vox_live.dart';
import 'theme.dart';
import 'util/i18n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Premiere's site takes seconds to load in its hidden page, and VOX's
  // listing a moment: start both alongside the catalog, so a film opened
  // early doesn't wait for them.
  PremiereLive.instance.warmUp();
  VoxLive.instance.warmUp();
  // And about hourly in the background, so they're fresh without opening the app.
  BackgroundRefresh.schedule();
  runApp(
    App(
      repository: FallbackShowtimesRepository(
        SupabaseShowtimesRepository(),
        AssetShowtimesRepository(),
      ),
    ),
  );
}

class App extends StatefulWidget {
  const App({super.key, required this.repository});

  final ShowtimesRepository repository;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  AppData? _data;
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyLook(rebuild: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _data?.prefs.removeListener(_applyLook);
    _data?.prefs.removeListener(_syncWidget);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _applyLook();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Push.instance.refresh();
      Usage.recordOpen();
    }
  }

  /// Light or dark and Arabic or English, from Settings (or the phone).
  /// Colours and strings are read while building, so on a change every
  /// widget rebuilds — const ones included.
  void _applyLook({bool rebuild = true}) {
    final prefs = _data?.prefs;
    final phoneDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final palette = switch (prefs?.appearance ?? Appearance.system) {
      Appearance.light => Palette.light,
      Appearance.dark => Palette.dark,
      Appearance.system => phoneDark ? Palette.dark : Palette.light,
    };
    final english = prefs?.english ?? false;
    if (rebuild && palette == AppColors.palette && english == Lang.english) {
      return;
    }
    AppColors.palette = palette;
    Lang.english = english;
    final dark = palette.brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: palette.brightness,
        systemNavigationBarColor: palette.background,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
    if (!rebuild || !mounted) return;
    setState(() {});
    void markAll(Element e) {
      e.markNeedsBuild();
      e.visitChildren(markAll);
    }

    (context as Element).visitChildren(markAll);
  }

  void _ready(AppData data, {bool stale = false}) {
    data.refresh = _refresh;
    setState(() => _data = data);
    // Opened on last time's catalog: fetch today's behind it.
    if (stale) _refresh();
    data.prefs.addListener(_applyLook);
    // Starring a cinema or switching language changes what the widget shows.
    data.prefs.addListener(_syncWidget);
    _syncWidget();
    _applyLook();
    // A tapped "tickets are out" notification opens its film.
    Push.instance.onOpenFilm = (movieId) {
      final movie = _data?.catalog.movies[movieId];
      final context = _navigator.currentContext;
      if (movie != null && context != null) openFilm(context, movie);
    };
    // A showtimes notification opens what it was about: which films, where
    // and when.
    Push.instance.onOpenAlert = (news) {
      final context = _navigator.currentContext;
      if (context != null) openNews(context, news);
    };
    Push.instance.start(data.prefs);
    Usage.recordOpen();
  }

  void _syncWidget() {
    final data = _data;
    if (data != null) syncHomeWidget(data);
  }

  /// The latest showtimes from Supabase, swapped in under whatever screen is
  /// open. A failed fetch keeps what's there.
  Future<void> _refresh() async {
    final current = _data;
    if (current == null) return;
    final repo = widget.repository;
    final live = repo is FallbackShowtimesRepository ? repo.primary : repo;
    try {
      final catalog = await live.load();
      if (!mounted || catalog.showtimes.isEmpty) return;
      final fresh = AppData(catalog, current.prefs)..refresh = _refresh;
      setState(() => _data = fresh);
      _syncWidget();
    } catch (e) {
      debugPrint('Refreshing showtimes failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: tr('عالشباك', '3al Shebbak'),
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      scrollBehavior: const _DragToScroll(),
      // Arabic lays the whole app out right-to-left, English left-to-right.
      locale: Lang.english ? const Locale('en') : const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Above the Navigator, so pushed pages and sheets see the data too.
      builder: (context, child) =>
          _data == null ? child! : AppScope(data: _data!, child: child!),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: switch (_data) {
          null => SplashScreen(repository: widget.repository, onReady: _ready),
          final data when !data.prefs.onboarded => OnboardingScreen(
            onDone: () => setState(() {}),
          ),
          _ => const Shell(),
        },
      ),
    );
  }
}

/// Rows of pills and cards drag with a mouse too, not only a finger — on the
/// web a horizontal list otherwise only moves with a trackpad or shift+wheel.
class _DragToScroll extends MaterialScrollBehavior {
  const _DragToScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}
