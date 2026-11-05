import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import 'common.dart';
import 'ticket_mark.dart';

/// Sends a film's showtimes to friends as a picture: a ticket-like card with
/// the poster and the times, previewed first. With [imageOnly] the picture
/// goes alone; otherwise the text (with the booking link) goes along too.
/// The text is also the fallback if the picture can't be made.
Future<void> shareShowtimes(
  BuildContext context, {
  required Movie movie,
  required List<Showtime> shows,
  required String heading,
  required String text,
  bool imageOnly = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SharePreview(
      movie: movie,
      shows: [...shows]..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
      heading: heading,
      text: text,
      imageOnly: imageOnly,
    ),
  );
}

class _SharePreview extends StatefulWidget {
  const _SharePreview({
    required this.movie,
    required this.shows,
    required this.heading,
    required this.text,
    this.imageOnly = false,
  });

  final Movie movie;
  final List<Showtime> shows;
  final String heading;
  final String text;
  final bool imageOnly;

  @override
  State<_SharePreview> createState() => _SharePreviewState();
}

class _SharePreviewState extends State<_SharePreview> {
  final _card = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              png!.buffer.asUint8List(),
              mimeType: 'image/png',
              name: '3alshebbak.png',
            ),
          ],
          fileNameOverrides: ['3alshebbak.png'],
          text: widget.imageOnly ? null : widget.text,
        ),
      );
    } catch (e) {
      debugPrint('Sharing the card as an image failed ($e); sending text');
      await SharePlus.instance.share(ShareParams(text: widget.text));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _card,
                child: ShowtimesCard(
                  movie: widget.movie,
                  shows: widget.shows,
                  heading: widget.heading,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _sharing ? null : _share,
            icon: _sharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share, size: 18),
            label: Text(tr('ابعتها', 'Share')),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.onGold,
              minimumSize: const Size.fromHeight(52),
              textStyle: AppText.body(16, weight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The picture itself: poster and title over the times, a perforated edge
/// like a ticket stub, and the app's mark at the foot.
class ShowtimesCard extends StatelessWidget {
  const ShowtimesCard({
    super.key,
    required this.movie,
    required this.shows,
    required this.heading,
  });

  final Movie movie;
  final List<Showtime> shows;
  final String heading;

  /// More than this and the card would scroll off a phone screen.
  static const _shown = 6;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final rest = shows.length - _shown;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.raised, AppColors.background],
        ),
        border: Border.all(color: AppColors.goldEdge.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Poster(movie: movie, width: 92, height: 138, radius: 12),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: AppText.body(
                          13,
                          weight: FontWeight.w700,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        movie.displayTitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.display(26),
                      ),
                      if (movie.genres.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          movie.genres.take(2).join(' · '),
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _Perforation(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
            child: Column(
              children: [
                for (final s in shows.take(_shown))
                  _ShowRow(show: s, cinema: data.cinema(s.cinemaId)),
                if (rest > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr('و$rest مواعيد كمان', 'and $rest more'),
                      style: AppText.body(12, color: AppColors.muted),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const TicketMark(size: 26),
                const SizedBox(width: 8),
                Text(
                  'عالشباك',
                  style: AppText.display(20, color: AppColors.gold),
                ),
                const SizedBox(width: 8),
                Text(
                  '3AL SHEBBAK',
                  style: AppText.numerals(
                    12,
                    color: AppColors.muted,
                  ).copyWith(letterSpacing: 3),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'by Abdallah Saeed 🍿',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: AppText.body(
                10,
                weight: FontWeight.w600,
                color: AppColors.muted,
              ).copyWith(letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShowRow extends StatelessWidget {
  const _ShowRow({required this.show, required this.cinema});

  final Showtime show;
  final Cinema cinema;

  @override
  Widget build(BuildContext context) {
    final wall = show.wallClock;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clock(wall),
                style: AppText.numerals(28, color: AppColors.gold),
              ),
              Text(
                period(wall),
                style: AppText.body(11, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayLabel(show.businessDate),
                  style: AppText.body(13, weight: FontWeight.w700),
                ),
                Text(
                  cinema.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (show.format.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.perforation),
              ),
              child: Text(
                show.format,
                style: AppText.body(11, weight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

/// The dashed tear line between the stub and the times, notched at the ends.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 20,
    child: CustomPaint(
      painter: _PerforationPainter(
        notch: AppColors.background,
        dash: AppColors.perforation,
      ),
    ),
  );
}

class _PerforationPainter extends CustomPainter {
  _PerforationPainter({required this.notch, required this.dash});

  final Color notch;
  final Color dash;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final fill = Paint()..color = notch;
    canvas.drawCircle(Offset(0, y), 10, fill);
    canvas.drawCircle(Offset(size.width, y), 10, fill);
    final line = Paint()
      ..color = dash
      ..strokeWidth = 2;
    for (var x = 18.0; x < size.width - 18; x += 12) {
      canvas.drawLine(Offset(x, y), Offset(x + 6, y), line);
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) =>
      old.notch != notch || old.dash != dash;
}
