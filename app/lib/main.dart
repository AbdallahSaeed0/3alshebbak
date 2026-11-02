import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/app_data.dart';
import 'data/prefs.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';
import 'screens/film_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'services/push.dart';
import 'theme.dart';
import 'util/i18n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _applyLook();

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

  void _ready(AppData data) {
    setState(() => _data = data);
    data.prefs.addListener(_applyLook);
    _applyLook();
    // A tapped "tickets are out" notification opens its film.
    Push.instance.onOpenFilm = (movieId) {
      final movie = _data?.catalog.movies[movieId];
      final context = _navigator.currentContext;
      if (movie != null && context != null) openFilm(context, movie);
    };
    Push.instance.start(data.prefs);
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
