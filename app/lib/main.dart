import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/app_data.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF110F0C),
    ),
  );
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

class _AppState extends State<App> {
  AppData? _data;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'عالشباك',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Arabic-first: the whole app lays out right-to-left.
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Above the Navigator, so pushed pages and sheets see the data too.
      builder: (context, child) =>
          _data == null ? child! : AppScope(data: _data!, child: child!),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: _data == null
            ? SplashScreen(
                repository: widget.repository,
                onReady: (d) => setState(() => _data = d),
              )
            : const Shell(),
      ),
    );
  }
}
