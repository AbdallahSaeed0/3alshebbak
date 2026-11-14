import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/halls.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/i18n.dart';
import '../util/links.dart';
import 'showtime_sheet.dart' show bookingSite;

void openSeatView(
  BuildContext context,
  Hall hall, {
  Movie? movie,
  String? bookingUrl,
}) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SeatViewScreen(hall: hall, movie: movie, bookingUrl: bookingUrl),
      ),
    )
    // back on the ticket: have the hall ready again for another look
    .then((_) {
      if (context.mounted) {
        SeatViewPreload.warm(
          context,
          hall,
          movie: movie,
          bookingUrl: bookingUrl,
        );
      }
    });

/// The 3D hall, built in a hidden web view as soon as a show's ticket opens,
/// so "pick your seat" opens on a hall that's already drawn instead of
/// starting the web view, three.js and the shaders from scratch (~3 s on a
/// phone). One at a time; one nobody opens is let go after a few minutes.
class SeatViewPreload {
  SeatViewPreload._(this._key);

  static const page = 'assets/seatview/index.html';
  static SeatViewPreload? _current;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // No disableHorizontalScroll/disableVerticalScroll: on Android, with both
  // set the plugin swallows every finger move, so the hall couldn't be
  // dragged. The page doesn't scroll anyway (overflow hidden, touch-action
  // none).
  static InAppWebViewSettings settings() =>
      InAppWebViewSettings(supportZoom: false, disallowOverScroll: true);

  /// Drags move around the hall, not the page.
  static final drags = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  /// The page's messages: 'ready', 'failed', 'seat' (id), 'book' (id).
  static void listen(
    InAppWebViewController c,
    void Function(String name, List<dynamic> args) on,
  ) {
    for (final name in const ['ready', 'failed', 'seat', 'book']) {
      c.addJavaScriptHandler(
        handlerName: name,
        callback: (args) => on(name, args),
      );
    }
  }

  final String _key;
  late final HeadlessInAppWebView web;
  bool isReady = false;
  bool _failed = false;
  bool _taken = false;
  Timer? _expiry;

  /// The screen showing this page, once it has taken it.
  void Function(String name, List<dynamic> args)? listener;

  static String _keyFor(Hall hall, Movie? movie, String? bookingUrl) => [
    hall.cinemaId,
    hall.name,
    movie?.backdropPath ?? movie?.posterPath,
    bookingUrl,
    Lang.english,
  ].join('|');

  /// Starts building [hall] in the background, unless it already is.
  static void warm(
    BuildContext context,
    Hall hall, {
    Movie? movie,
    String? bookingUrl,
  }) {
    if (!supported) return;
    final key = _keyFor(hall, movie, bookingUrl);
    final current = _current;
    if (current != null && current._key == key && !current._failed) {
      current._expireLater();
      return;
    }
    current?._release();
    final mq = MediaQuery.of(context);
    // the size the screen will have: below the app bar, above the system bar
    final height =
        (mq.size.height - mq.padding.top - kToolbarHeight - mq.padding.bottom) *
        mq.devicePixelRatio;
    final json = _SeatViewScreenState.hallJson(
      hall,
      movie: movie,
      bookingUrl: bookingUrl,
      start: hall.bestSeat,
    );
    final p = SeatViewPreload._(key);
    p.web = HeadlessInAppWebView(
      initialFile: page,
      initialSize: Size(-1, height),
      initialSettings: settings(),
      onWebViewCreated: (c) => listen(c, p._onPage),
      onLoadStop: (c, _) => c.evaluateJavascript(source: 'setupHall($json)'),
    );
    _current = p;
    p._expireLater();
    p.web.run();
  }

  /// The page built for [hall], if there is one; the caller then owns it.
  static SeatViewPreload? take(Hall hall, {Movie? movie, String? bookingUrl}) {
    final p = _current;
    if (p == null || p._failed || p._key != _keyFor(hall, movie, bookingUrl)) {
      return null;
    }
    _current = null;
    p._taken = true;
    p._expiry?.cancel();
    return p;
  }

  void _onPage(String name, List<dynamic> args) {
    if (name == 'ready') isReady = true;
    if (name == 'failed') _failed = true;
    listener?.call(name, args);
  }

  void _expireLater() {
    _expiry?.cancel();
    _expiry = Timer(const Duration(minutes: 3), () {
      if (identical(_current, this)) _current = null;
      _release();
    });
  }

  void _release() {
    _expiry?.cancel();
    if (!_taken) web.dispose();
  }
}

/// How good a seat is, in three steps the map can show at a glance.
enum _Tier { best, good, plain }

_Tier _tierOf(double score) => score >= 0.85
    ? _Tier.best
    : score >= 0.62
    ? _Tier.good
    : _Tier.plain;

/// "Which seat is best?": the screen as seen from a seat, and the hall's real
/// seat map with the best seats lit. Tap a seat to sit in it.
class SeatViewScreen extends StatefulWidget {
  const SeatViewScreen({
    super.key,
    required this.hall,
    this.movie,
    this.backdrop,
    this.seat,
    this.bookingUrl,
  });

  final Hall hall;
  final Movie? movie;

  /// The show's page on the booking site, for the "book" button. The site
  /// can't be told the seat, so the person is reminded which one they chose.
  final String? bookingUrl;

  /// The picture for the screen when it's already at hand (else the film's
  /// TMDB backdrop is fetched), and the seat to start in (else the best).
  final ui.Image? backdrop;
  final Seat? seat;

  @override
  State<SeatViewScreen> createState() => _SeatViewScreenState();
}

class _SeatViewScreenState extends State<SeatViewScreen> {
  late Seat _seat = widget.seat ?? widget.hall.bestSeat;
  late final Map<Seat, _Tier> _tiers = {
    for (final s in widget.hall.seats)
      s: _tierOf(widget.hall.viewFrom(s).score),
  };
  late ui.Image? _backdrop = widget.backdrop;

  /// The 3D hall explorer (assets/seatview/index.html) fills the screen on
  /// phones; the flat drawing below is for everywhere else, and for phones
  /// whose web view can't draw 3D.
  static bool get _has3d =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool _ready = false;
  bool _failed = false;

  /// Set when the hall was already built in the background (from the show's
  /// ticket): the screen shows that page instead of loading its own.
  SeatViewPreload? _preload;

  static (String, String) _rating(SeatView v) => switch (v.issue) {
    null => (tr('مثالي', 'Ideal'), 'good'),
    ViewIssue.close => (tr('قريب', 'Close'), 'ok'),
    ViewIssue.aBitFar => (tr('بعيد شوية', 'A bit far'), 'ok'),
    ViewIssue.tooClose => (tr('قريب أوي', 'Too close'), 'bad'),
    ViewIssue.farBack => (tr('بعيد', 'Far back'), 'bad'),
    ViewIssue.toTheSide => (tr('على الجنب', 'Side angle'), 'bad'),
  };

  /// Everything the 3D page draws, worked out here so its positions and
  /// ratings are the same ones the rest of the app uses.
  static String hallJson(
    Hall h, {
    Movie? movie,
    String? bookingUrl,
    required Seat start,
  }) {
    final g = h.geometry;
    final booking = bookingUrl;
    final path = movie?.backdropPath ?? movie?.posterPath;
    return jsonEncode({
      'lang': Lang.english ? 'en' : 'ar',
      'free': h.freeSeating,
      'motion': h.formats.join(' ').toUpperCase().contains('4D'),
      'screen': {
        'w': g.screenWidth,
        'h': g.screenHeight,
        'bottom': g.screenBottom,
        'curve': g.curve,
      },
      'columns': h.columns,
      'depths': h.depths,
      'firstRow': g.firstRowDistance,
      'rowDepth': g.rowDepth,
      'rise': g.rise,
      'seatWidth': g.seatWidth,
      'image': path == null ? null : 'https://image.tmdb.org/t/p/w1280$path',
      'best': h.seats.indexOf(h.bestSeat),
      'start': h.seats.indexOf(start),
      'text': {
        'row': tr('صف', 'Row'),
        'seat': tr('كرسي', 'Seat'),
        'selected': h.freeSeating
            ? tr('جلوس حر · مكان مقترح', 'Free seating · a suggested spot')
            : tr('الكرسي اللي اخترته', 'Your seat'),
        'yourView': tr('المنظر من كرسيك', 'Your view'),
        'viewFrom': tr('شوف من هنا', 'View from seat'),
        'overview': tr('القاعة كلها', 'Whole hall'),
        'best': tr('أحسن كرسي', 'Best seat'),
        'book': booking == null
            ? null
            : tr(
                'احجز على موقع ${bookingSite(booking)}',
                'Book on ${bookingSite(booking)}',
              ),
        'viewFromShort': tr('المنظر من', 'View from'),
        'expand': tr('كبّر', 'Expand'),
        'noGl': tr(
          'العرض الـ3D مش شغال على الموبايل ده',
          '3D view isn\'t available on this phone',
        ),
      },
      'seats': [
        for (final s in h.seats)
          () {
            final (label, tone) = _rating(h.viewFrom(s));
            return {
              'id': s.label,
              'row': s.row,
              'num': s.number,
              'c': s.col,
              'd': s.depth,
              'x': h.seatX(s),
              'y': h.floorY(s.depth),
              'z': h.seatZ(s),
              'r': label,
              'k': tone,
            };
          }(),
      ],
    });
  }

  void _select(Seat s) => setState(() => _seat = s);

  /// A message from the 3D page.
  void _onPage(String name, List<dynamic> args) {
    if (!mounted) return;
    final s = _seatById(args.isEmpty ? null : args.first);
    switch (name) {
      case 'ready':
        setState(() => _ready = true);
      case 'failed':
        setState(() => _failed = true);
      case 'seat':
        if (s != null) _seat = s;
      case 'book':
        _book(s ?? _seat);
    }
  }

  Seat? _seatById(Object? id) {
    for (final s in widget.hall.seats) {
      if (s.label == id) return s;
    }
    return null;
  }

  /// Off to the booking site, with a reminder of the seat: the site can't be
  /// told which one.
  void _book(Seat s) {
    final url = widget.bookingUrl;
    if (url == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            widget.hall.freeSeating
                ? tr(
                    'الجلوس حر: اقعد في صف ${s.row} أو جنبه',
                    'Free seating: sit in row ${s.row} or near it',
                  )
                : tr(
                    'اختار صف ${s.row} كرسي ${s.number} في صفحة الحجز',
                    'Pick row ${s.row}, seat ${s.number} on the booking page',
                  ),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    openSite(url);
  }

  PreferredSizeWidget _appBar() => AppBar(
    title: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            tr('اختار كرسيك', 'Pick your seat'),
            style: AppText.display(22),
          ),
        ),
        const SizedBox(width: 8),
        const BetaTag(),
      ],
    ),
    backgroundColor: AppColors.background,
  );

  Widget _build3d() => Scaffold(
    appBar: _appBar(),
    backgroundColor: const Color(0xFF0B0A08),
    // Clear of Android's navigation bar, so the buttons at the bottom of the
    // page aren't under it.
    body: SafeArea(
      top: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: _ready ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: _preload != null
                ? InAppWebView(
                    headlessWebView: _preload!.web,
                    gestureRecognizers: SeatViewPreload.drags,
                  )
                : InAppWebView(
                    initialFile: SeatViewPreload.page,
                    initialSettings: SeatViewPreload.settings(),
                    gestureRecognizers: SeatViewPreload.drags,
                    onWebViewCreated: (c) =>
                        SeatViewPreload.listen(c, (n, a) => _onPage(n, a)),
                    onLoadStop: (c, _) => c.evaluateJavascript(
                      source:
                          'setupHall(${hallJson(widget.hall, movie: widget.movie, bookingUrl: widget.bookingUrl, start: _seat)})',
                    ),
                  ),
          ),
          if (!_ready)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    ),
  );

  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    if (_has3d && widget.seat == null) {
      _preload = SeatViewPreload.take(
        widget.hall,
        movie: widget.movie,
        bookingUrl: widget.bookingUrl,
      );
      final p = _preload;
      if (p != null) {
        _ready = p.isReady;
        p.listener = _onPage;
      }
    }
    final path = widget.movie?.backdropPath ?? widget.movie?.posterPath;
    if (_backdrop == null && path != null) {
      _stream = NetworkImage(
        'https://image.tmdb.org/t/p/w780$path',
      ).resolve(ImageConfiguration.empty);
      _listener = ImageStreamListener((info, _) {
        if (mounted) setState(() => _backdrop = info.image);
      }, onError: (_, _) {});
      _stream!.addListener(_listener!);
    }
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _preload?.listener = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_has3d && !_failed) return _build3d();
    final hall = widget.hall;
    final view = hall.viewFrom(_seat);
    final tier = _tierOf(view.score);
    final booking = widget.bookingUrl;
    return Scaffold(
      appBar: _appBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // The view from the seat. Left and right are the hall's, whatever
          // the app's language.
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: CustomPaint(
                      painter: _ViewPainter(hall, _seat, _backdrop),
                    ),
                  ),
                  PositionedDirectional(
                    start: 12,
                    top: 12,
                    child: _SeatBadge(seat: _seat, tier: tier),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(_why(view), style: AppText.body(15, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Fact(
                icon: Icons.panorama_wide_angle_outlined,
                text: tr(
                  'الشاشة ${view.screenAngle.round()}° من نظرك',
                  'Screen fills ${view.screenAngle.round()}°',
                ),
              ),
              _Fact(
                icon: Icons.swap_horiz,
                text: view.sideAngle < 3
                    ? tr('في النص', 'Centred')
                    : tr(
                        '${view.sideAngle.round()}° على الجنب',
                        '${view.sideAngle.round()}° off centre',
                      ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Directionality(
            textDirection: TextDirection.ltr,
            child: _SeatMap(
              hall: hall,
              tiers: _tiers,
              selected: _seat,
              onSelect: _select,
            ),
          ),
          const SizedBox(height: 12),
          const _Legend(),
          if (booking != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _book(_seat),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(
                tr(
                  'احجز على موقع ${bookingSite(booking)}',
                  'Book on ${bookingSite(booking)}',
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.onGold,
                minimumSize: const Size.fromHeight(52),
                textStyle: AppText.body(16, weight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            tr(
              'ترتيب الكراسي من موقع الحجز. حجم الشاشة والمسافات تقريبية.',
              'Seat layout from the booking site. Screen size and distances are approximate.',
            ),
            textAlign: TextAlign.center,
            style: AppText.body(11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  static String _why(SeatView v) => switch (v.issue) {
    ViewIssue.tooClose => tr(
      'قريب أوي: هتبص لفوق وتلف راسك.',
      'Too close: you\'ll look up and turn your head.',
    ),
    ViewIssue.close => tr(
      'قريب: الشاشة مالية نظرك، لو بتحب تبقى جوا الفيلم.',
      'Close: the screen fills your view, if you like being in the film.',
    ),
    ViewIssue.aBitFar => tr(
      'بعيد شوية: مريح بس الشاشة أصغر.',
      'A bit far: comfortable, the screen looks smaller.',
    ),
    ViewIssue.farBack => tr(
      'بعيد: الشاشة هتبان صغيرة.',
      'Far back: the screen looks small.',
    ),
    ViewIssue.toTheSide => tr(
      'على الجنب: هتشوف الشاشة مايلة.',
      'To the side: you see the screen at an angle.',
    ),
    null => tr(
      'مكان مثالي: الشاشة مالية نظرك من غير ما تلف راسك.',
      'Spot on: the screen fills your view without turning your head.',
    ),
  };
}

class _SeatBadge extends StatelessWidget {
  const _SeatBadge({required this.seat, required this.tier});

  final Seat seat;
  final _Tier tier;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (tier) {
      _Tier.best => (tr('ممتاز', 'Excellent'), AppColors.gold),
      _Tier.good => (tr('كويس', 'Good'), const Color(0xFFE3C98F)),
      _Tier.plain => (tr('عادي', 'So-so'), const Color(0xFFBDB6AE)),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xCC0E0C0B),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(
              'صف ${seat.row} · كرسي ${seat.number}',
              'Row ${seat.row} · Seat ${seat.number}',
            ),
            style: AppText.body(
              13,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              label,
              style: AppText.body(
                12,
                weight: FontWeight.w800,
                color: const Color(0xFF1A1512),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.raised,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 6),
        Text(text, style: AppText.body(12, color: AppColors.muted)),
      ],
    ),
  );
}

Color _tierColor(_Tier t) => switch (t) {
  _Tier.best => AppColors.gold,
  _Tier.good => AppColors.gold.withValues(alpha: 0.45),
  _Tier.plain => AppColors.hairline,
};

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(_Tier t, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _tierColor(t),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.body(12, color: AppColors.muted)),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      children: [
        item(_Tier.best, tr('ممتاز', 'Excellent')),
        item(_Tier.good, tr('كويس', 'Good')),
        item(_Tier.plain, tr('عادي', 'So-so')),
      ],
    );
  }
}

/// The hall from above, the screen as a curve at the top. One painter and one
/// tap handler for every seat: hundreds of small widgets would be slow and
/// hard to hit.
class _SeatMap extends StatelessWidget {
  const _SeatMap({
    required this.hall,
    required this.tiers,
    required this.selected,
    required this.onSelect,
  });

  final Hall hall;
  final Map<Seat, _Tier> tiers;
  final Seat selected;
  final ValueChanged<Seat> onSelect;

  static const _top = 34.0; // room for the screen curve

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cell = box.maxWidth / (hall.columns + 2);
      final height = _top + cell * hall.depths + 4;
      return GestureDetector(
        onTapDown: (d) {
          Seat? best;
          var bestDist = double.infinity;
          for (final s in hall.seats) {
            final dist = (_center(s, cell) - d.localPosition).distanceSquared;
            if (dist < bestDist) {
              bestDist = dist;
              best = s;
            }
          }
          if (best != null && bestDist < cell * cell * 3) onSelect(best);
        },
        child: CustomPaint(
          size: Size(box.maxWidth, height),
          painter: _MapPainter(hall, tiers, selected, cell),
        ),
      );
    },
  );

  static Offset _center(Seat s, double cell) =>
      Offset(cell * (1.5 + s.col), _top + cell * (0.5 + s.depth));
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.hall, this.tiers, this.selected, this.cell);

  final Hall hall;
  final Map<Seat, _Tier> tiers;
  final Seat selected;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // The screen: a soft curve with a glow under it.
    final curve = Path()
      ..moveTo(w * 0.18, 16)
      ..quadraticBezierTo(w / 2, 4, w * 0.82, 16);
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = AppColors.gold.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AppColors.gold,
    );

    // Row letters at the side.
    final letter = TextStyle(
      color: AppColors.muted,
      fontSize: (cell * 0.62).clamp(7, 12),
      fontWeight: FontWeight.w600,
    );
    for (var d = 0; d < hall.depths; d++) {
      final name = hall.rowNames[d];
      if (name.isEmpty || !hall.seats.any((s) => s.depth == d)) continue;
      final tp = TextPainter(
        text: TextSpan(text: name, style: letter),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          cell * 0.5 - tp.width / 2,
          _SeatMap._top + cell * (0.5 + d) - tp.height / 2,
        ),
      );
    }

    final inset = math.max(1.2, cell * 0.16);
    for (final s in hall.seats) {
      final c = _SeatMap._center(s, cell);
      final r = RRect.fromRectAndCorners(
        Rect.fromCenter(center: c, width: cell - inset, height: cell - inset),
        // A seat: rounder at the back.
        topLeft: Radius.circular(cell * 0.32),
        topRight: Radius.circular(cell * 0.32),
        bottomLeft: Radius.circular(cell * 0.14),
        bottomRight: Radius.circular(cell * 0.14),
      );
      final isSelected = identical(s, selected);
      canvas.drawRRect(
        r,
        Paint()
          ..color = isSelected
              ? Colors.white
              : _tierColor(tiers[s] ?? _Tier.plain),
      );
      if (isSelected) {
        canvas.drawRRect(
          r.inflate(inset + 1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => !identical(old.selected, selected);
}

/// The hall in perspective from a seat: the screen showing the film's image,
/// and the nearest rows in front as silhouettes.
class _ViewPainter extends CustomPainter {
  _ViewPainter(this.hall, this.seat, this.image);

  final Hall hall;
  final Seat seat;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final g = hall.geometry;
    // Eyes at the seat, looking at the middle of the screen.
    final cam = _V(hall.seatX(seat), hall.eyeY(seat), hall.seatZ(seat));
    // Looking at the middle of the screen, as you would.
    final target = _V(0, g.screenBottom + g.screenHeight * 0.45, 0);
    final f = (target - cam).normalized;
    final r = f.cross(const _V(0, 1, 0)).normalized;
    final u = r.cross(f);
    // About 70° across, near what the eye takes in without turning. Wider
    // would stretch everything at the edges like a wide-angle lens.
    final focal = size.width / 2 / math.tan(35 * math.pi / 180);
    final mid = Offset(size.width / 2, size.height * 0.46);

    Offset? project(_V p) {
      final d = p - cam;
      final depth = d.dot(f);
      if (depth < 0.3) return null;
      return mid + Offset(d.dot(r) / depth * focal, -d.dot(u) / depth * focal);
    }

    // The dark hall, lit a little by the screen.
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = const Color(0xFF09080A));

    // The screen as a mesh following its curve: a single quad would skew the
    // picture, since a texture across two triangles ignores perspective.
    final sw = g.screenWidth / 2;
    _V onScreen(double a, double b) {
      final x = -sw + a * 2 * sw;
      return _V(
        x,
        g.screenBottom + (1 - b) * g.screenHeight,
        g.curve * (x / sw) * (x / sw),
      );
    }

    const nx = 28, ny = 14;
    final grid = [
      for (var j = 0; j <= ny; j++)
        [for (var i = 0; i <= nx; i++) project(onScreen(i / nx, j / ny))],
    ];
    final outline = <Offset>[
      for (var i = 0; i <= nx; i++) ?grid[0][i],
      for (var j = 0; j <= ny; j++) ?grid[j][nx],
      for (var i = nx; i >= 0; i--) ?grid[ny][i],
      for (var j = ny; j >= 0; j--) ?grid[j][0],
    ];
    if (outline.length > 3) {
      final screen = Path()..addPolygon(outline, true);
      final glowRect = screen.getBounds();
      // Light spilling into the hall.
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(
              (glowRect.center.dx / size.width) * 2 - 1,
              (glowRect.center.dy / size.height) * 2 - 1,
            ),
            radius: 1.1,
            colors: const [Color(0x553A3024), Color(0x0009080A)],
          ).createShader(bounds),
      );
      _paintScreen(canvas, grid, nx, ny, screen);
    }

    // The nearest rows in front, as seat backs and heads.
    final ahead =
        hall.seats
            .where((s) => s.depth < seat.depth && s.depth >= seat.depth - 4)
            .toList()
          ..sort((a, b) => a.depth.compareTo(b.depth));
    for (final s in ahead) {
      final x = hall.seatX(s), z = hall.seatZ(s) + 0.3;
      final floor = hall.floorY(s.depth);
      final w = g.seatWidth * 0.42;
      final tl = project(_V(x - w, floor + 1.0, z));
      final br = project(_V(x + w, floor + 0.2, z));
      if (tl == null || br == null) continue;
      final rect = Rect.fromPoints(tl, br);
      final rr = RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(rect.width * 0.35),
        topRight: Radius.circular(rect.width * 0.35),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2C2420), Color(0xFF120F0D)],
          ).createShader(rect),
      );
      // A thin lit edge from the screen.
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0x33E6C27A),
      );
    }

    // Vignette, for a cinema's darkness at the edges.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.05,
          colors: [Color(0x00000000), Color(0x99000000)],
        ).createShader(bounds),
    );
  }

  /// The screen: the film's image laid over the mesh, or a warm glow until
  /// the image loads.
  void _paintScreen(
    Canvas canvas,
    List<List<Offset?>> grid,
    int nx,
    int ny,
    Path screen,
  ) {
    canvas.drawPath(
      screen,
      Paint()
        ..color = const Color(0x55E6C27A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    final img = image;
    if (img == null) {
      canvas.drawPath(
        screen,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2E3C2), Color(0xFFC9A464)],
          ).createShader(screen.getBounds()),
      );
      return;
    }
    // Crop the image to the screen's shape, centred.
    final aspect = hall.geometry.aspect;
    var cw = img.width.toDouble(), ch = cw / aspect;
    if (ch > img.height) {
      ch = img.height.toDouble();
      cw = ch * aspect;
    }
    final ox = (img.width - cw) / 2, oy = (img.height - ch) / 2;
    Offset tex(int i, int j) => Offset(ox + cw * i / nx, oy + ch * j / ny);

    final pos = <double>[], uv = <double>[];
    void corner(int i, int j) {
      final p = grid[j][i]!, t = tex(i, j);
      pos.addAll([p.dx, p.dy]);
      uv.addAll([t.dx, t.dy]);
    }

    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        if (grid[j][i] == null ||
            grid[j][i + 1] == null ||
            grid[j + 1][i] == null ||
            grid[j + 1][i + 1] == null) {
          continue;
        }
        corner(i, j);
        corner(i + 1, j);
        corner(i + 1, j + 1);
        corner(i, j);
        corner(i + 1, j + 1);
        corner(i, j + 1);
      }
    }
    if (pos.isEmpty) return;
    canvas.drawVertices(
      ui.Vertices.raw(
        VertexMode.triangles,
        Float32List.fromList(pos),
        textureCoordinates: Float32List.fromList(uv),
      ),
      BlendMode.srcOver,
      Paint()
        ..shader = ImageShader(
          img,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
        )
        ..filterQuality = FilterQuality.medium,
    );
    // The projector's light: a touch brighter in the middle.
    canvas.drawPath(
      screen,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x22FFFFFF), Color(0x00000000)],
        ).createShader(screen.getBounds()),
    );
  }

  @override
  bool shouldRepaint(_ViewPainter old) =>
      !identical(old.seat, seat) || old.image != image;
}

/// A point or direction in the hall, in metres.
class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  _V get normalized => _V(x / length, y / length, z / length);
}

/// "Still being tried out": hall layouts are recorded by hand and the screen
/// sizes are typical ones, so the feature says so wherever it's offered.
class BetaTag extends StatelessWidget {
  const BetaTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.gold.withValues(alpha: 0.7)),
    ),
    child: Text(
      tr('تجريبي', 'Beta'),
      style: AppText.body(10.5, color: AppColors.gold, weight: FontWeight.w700),
    ),
  );
}
