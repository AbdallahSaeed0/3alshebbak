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

void openSeatView(BuildContext context, Hall hall, {Movie? movie}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeatViewScreen(hall: hall, movie: movie),
      ),
    );

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
  });

  final Hall hall;
  final Movie? movie;

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

  /// The 3D hall (assets/seatview/index.html), on phones; the flat drawing
  /// shows until it's ready, and instead of it elsewhere.
  static bool get _has3d =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  InAppWebViewController? _web;
  bool _ready = false;

  String get _imageUrl {
    final path = widget.movie?.backdropPath ?? widget.movie?.posterPath;
    return path == null ? '' : 'https://image.tmdb.org/t/p/w1280$path';
  }

  /// Everything the 3D page draws, worked out here so its numbers are the
  /// same ones the ratings use.
  String _hallJson() {
    final h = widget.hall, g = h.geometry;
    return jsonEncode({
      'screen': {
        'w': g.screenWidth,
        'h': g.screenHeight,
        'bottom': g.screenBottom,
        'curve': g.curve,
      },
      'width': h.columns * g.seatWidth,
      'depth': h.seatZ(h.seats.last),
      'firstRow': g.firstRowDistance,
      'rowDepth': g.rowDepth,
      'rise': g.rise,
      'seatWidth': g.seatWidth,
      'image': _imageUrl.isEmpty ? null : _imageUrl,
      'seats': [
        for (final s in h.seats)
          {
            'id': s.label,
            'x': h.seatX(s),
            'y': h.floorY(s.depth),
            'z': h.seatZ(s),
            'd': s.depth,
            't': _tiers[s]!.index,
          },
      ],
    });
  }

  void _sit3d() {
    final h = widget.hall;
    _web?.evaluateJavascript(
      source:
          'sit(${jsonEncode(_seat.label)}, ${h.seatX(_seat)}, ${h.eyeY(_seat)}, ${h.seatZ(_seat)})',
    );
  }

  void _select(Seat s) {
    setState(() => _seat = s);
    _sit3d();
  }

  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hall = widget.hall;
    final view = hall.viewFrom(_seat);
    final tier = _tierOf(view.score);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                tr('أنهي كرسي أحسن؟', 'Which seat is best?'),
                style: AppText.display(22),
              ),
            ),
            const SizedBox(width: 8),
            const BetaTag(),
          ],
        ),
        backgroundColor: AppColors.background,
      ),
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
                  if (_has3d)
                    AnimatedOpacity(
                      opacity: _ready ? 1 : 0,
                      duration: const Duration(milliseconds: 400),
                      child: InAppWebView(
                        initialFile: 'assets/seatview/index.html',
                        initialSettings: InAppWebViewSettings(
                          transparentBackground: true,
                          supportZoom: false,
                          disableHorizontalScroll: true,
                          disableVerticalScroll: true,
                          disallowOverScroll: true,
                        ),
                        // Drags turn your head in the hall, not the page.
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                          ),
                        },
                        onWebViewCreated: (c) {
                          _web = c;
                          c.addJavaScriptHandler(
                            handlerName: 'ready',
                            callback: (_) {
                              _sit3d();
                              if (mounted) setState(() => _ready = true);
                            },
                          );
                        },
                        onLoadStop: (c, _) => c.evaluateJavascript(
                          source: 'setupHall(${_hallJson()})',
                        ),
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
