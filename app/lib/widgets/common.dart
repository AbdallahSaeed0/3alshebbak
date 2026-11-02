import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/i18n.dart';

/// A movie poster, or — when there's no image yet — a warm block with the
/// title on it, so a card never looks broken.
/// Room to leave at the bottom of a tab's page so its last item scrolls
/// clear of the floating glass tab bar (the bar's height is already in the
/// bottom padding, since the Shell extends pages under it).
double barSpace(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 16;

class Poster extends StatelessWidget {
  const Poster({
    super.key,
    required this.movie,
    required this.width,
    required this.height,
    this.radius = 10,
  });

  final Movie movie;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.raised,
      alignment: AlignmentDirectional.bottomStart,
      padding: const EdgeInsets.all(8),
      child: Text(
        movie.displayTitle,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: AppText.display(width > 100 ? 18 : 12, color: AppColors.muted),
      ),
    );
    final url = movie.posterUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url == null
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}

/// A section title in display type, an optional subtitle, and "الكل".
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.color,
    this.onSeeAll,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Color? color;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: leading,
                  ),
                Text(
                  title,
                  style: AppText.display(24, color: color ?? AppColors.text),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppText.body(12, color: AppColors.muted),
                  ),
              ],
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.gold,
                minimumSize: const Size(44, 44),
              ),
              child: Text(
                tr('الكل', 'All'),
                style: AppText.body(
                  13,
                  color: AppColors.gold,
                  weight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row of glowing marquee bulbs, every other one dimmed.
class MarqueeBulbs extends StatelessWidget {
  const MarqueeBulbs({super.key, this.count = 9});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 6,
              height: 6,
              margin: EdgeInsetsDirectional.only(end: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(alpha: i.isEven ? 1 : 0.45),
                boxShadow: [BoxShadow(color: AppColors.gold, blurRadius: 8)],
              ),
            ),
        ],
      ),
    );
  }
}

/// A showtime as a small ticket: time on top, format under it.
class TimeChip extends StatelessWidget {
  const TimeChip({super.key, required this.showtime, this.onTap});

  final Showtime showtime;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr(
        '${clock(showtime.wallClock)} ${period(showtime.wallClock)}، ${shortFormat(showtime.format)}',
        '${clock(showtime.wallClock)} ${period(showtime.wallClock)}, ${shortFormat(showtime.format)}',
      ),
      child: Material(
        color: AppColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.perforation),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    clock(showtime.wallClock),
                    textDirection: TextDirection.ltr,
                    style: AppText.numerals(19),
                  ),
                  Text(
                    shortFormat(showtime.format),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                      10,
                      color: formatTint(showtime.format),
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color formatTint(String format) {
  final f = format.toLowerCase();
  if (f.contains('imax') || f.contains('max')) return AppColors.imax;
  if (f.contains('4dx') ||
      f.contains('mx4d') ||
      f.contains('dbox') ||
      f.contains('screenx'))
    return AppColors.fourDx;
  return AppColors.gold;
}

/// A punched-out half circle, for the notches at a ticket's tear line.
class Notch extends StatelessWidget {
  const Notch({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// A vertical or horizontal dashed tear line.
class Perforation extends StatelessWidget {
  const Perforation({super.key, this.vertical = true});

  final bool vertical;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashPainter(vertical),
    size: vertical
        ? const Size(2, double.infinity)
        : const Size(double.infinity, 2),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.vertical);
  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.perforation
      ..strokeWidth = 2;
    final length = vertical ? size.height : size.width;
    for (var p = 0.0; p < length; p += 8) {
      final end = (p + 4).clamp(0, length).toDouble();
      canvas.drawLine(
        vertical ? Offset(1, p) : Offset(p, 1),
        vertical ? Offset(1, end) : Offset(end, 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.vertical != vertical;
}
