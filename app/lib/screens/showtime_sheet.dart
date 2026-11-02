import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../util/i18n.dart';

Future<void> showShowtimeSheet(BuildContext context, Showtime showtime) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    builder: (_) => _ShowtimeSheet(showtime: showtime),
  );
}

/// Whose site a booking link opens, for the button label.
String bookingSite(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.contains('vox')) return 'VOX';
  if (host.contains('premiere')) return 'Premiere';
  if (host.contains('rnscinemas')) return 'Renaissance';
  if (host.contains('scenecinemas')) return 'Scene';
  if (host.contains('elcinema')) return 'elCinema';
  return tr('السينما', 'Cinema');
}

/// The show as a ticket: movie, a big start time, the details, a tear line,
/// then "book on the cinema's own site" — we never sell tickets ourselves.
class _ShowtimeSheet extends StatelessWidget {
  const _ShowtimeSheet({required this.showtime});

  final Showtime showtime;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context);
    final movie = data.movie(showtime.movieId);
    final cinema = data.cinema(showtime.cinemaId);
    final wall = showtime.wallClock;
    final until = showtime.startsAt.difference(data.now);
    final booking = showtime.bookingUrl;

    Widget field(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.body(11, color: AppColors.muted)),
        Text(value, style: AppText.body(14, weight: FontWeight.w700)),
      ],
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.perforation),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 14),
                  const Center(child: MarqueeBulbs(count: 11)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        Poster(movie: movie, width: 52, height: 78, radius: 8),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                movie.displayTitle,
                                style: AppText.display(26),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          clock(wall),
                          textDirection: TextDirection.ltr,
                          style: AppText.numerals(84, color: AppColors.gold)
                              .copyWith(
                                shadows: [
                                  Shadow(
                                    color: AppColors.gold.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 24,
                                  ),
                                ],
                              ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                wall.hour < 12 ? 'صباحًا' : 'مساءً',
                                style: AppText.body(
                                  16,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                startsIn(until),
                                style: AppText.body(
                                  12,
                                  color: AppColors.amber,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: field(
                                tr('اليوم', 'Day'),
                                dayLabel(showtime.businessDate),
                              ),
                            ),
                            Expanded(
                              child: field(
                                tr('السينما', 'Cinema'),
                                cinema.label,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: field(
                                tr('النوع', 'Format'),
                                showtime.format,
                              ),
                            ),
                            Expanded(
                              child: showtime.priceEgp != null
                                  ? field(
                                      tr('السعر', 'Price'),
                                      tr(
                                        '${showtime.priceEgp} جنيه',
                                        'EGP ${showtime.priceEgp}',
                                      ),
                                    )
                                  : field(
                                      tr('المنطقة', 'Area'),
                                      cinema.area ?? cinema.city ?? '—',
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 2,
                    child: Perforation(vertical: false),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (booking != null)
                          FilledButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(booking),
                              mode: LaunchMode.externalApplication,
                            ),
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
                              minimumSize: const Size.fromHeight(56),
                              textStyle: AppText.body(
                                16,
                                weight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => SharePlus.instance.share(
                            ShareParams(
                              text:
                                  '${movie.displayTitle} — ${clock(wall)} ${period(wall)}${tr('،', ',')} '
                                  '${dayLabel(showtime.businessDate)}\n${cinema.label} · ${showtime.format}'
                                  '${booking != null ? '\n$booking' : ''}',
                            ),
                          ),
                          icon: const Icon(Icons.ios_share, size: 18),
                          label: Text(tr('ابعتها لصحابك', 'Send to friends')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text,
                            side: BorderSide(color: AppColors.perforation),
                            minimumSize: const Size.fromHeight(48),
                            textStyle: AppText.body(
                              14,
                              weight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          cinema.attribution != null
                              ? tr(
                                  'المواعيد من ${cinema.attribution} · الحجز والدفع على موقع السينما',
                                  'Times from ${cinema.attribution} · booking and payment on the cinema\'s site',
                                )
                              : tr(
                                  'الحجز والدفع بيتم على موقع السينما نفسه',
                                  'Booking and payment happen on the cinema\'s own site',
                                ),
                          textAlign: TextAlign.center,
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
