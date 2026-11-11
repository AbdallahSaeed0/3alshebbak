import 'package:flutter/material.dart';

import '../data/models.dart';
import '../screens/showtime_sheet.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import '../util/i18n.dart';

/// Day picker: "النهارده", "بكرة", then weekday + date.
class DateStrip extends StatelessWidget {
  const DateStrip({
    super.key,
    required this.dates,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final List<String> dates;
  final String selected;
  final String today;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 20),
        itemCount: dates.length,
        separatorBuilder: (_, _) => SizedBox(width: 8),
        itemBuilder: (context, i) {
          final date = dates[i];
          final on = date == selected;
          final d = DateTime.parse(date);
          final name = date == today
              ? tr('النهارده', 'Today')
              : d.difference(DateTime.parse(today)).inHours ~/ 24 == 1
              ? tr('بكرة', 'Tomorrow')
              : dayLabel(date).split(' ').first;
          return Semantics(
            selected: on,
            button: true,
            label: dayLabel(date),
            child: Material(
              color: on ? AppColors.gold : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: on ? AppColors.gold : AppColors.hairline,
                ),
              ),
              child: InkWell(
                onTap: () => onSelect(date),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          style: AppText.body(
                            11,
                            color: on ? AppColors.onGold : AppColors.text,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${d.day}',
                          style: AppText.numerals(
                            24,
                            color: on ? AppColors.onGold : AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A row of single-choice filter pills; tapping the selected one clears it.
class FilterPills extends StatelessWidget {
  const FilterPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.allLabel,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  /// The first pill, which clears the choice. "All" unless given.
  final String? allLabel;

  @override
  Widget build(BuildContext context) {
    // Hand-built rather than ChoiceChip: the chip measured its label before the
    // web font loaded and clipped it.
    Widget pill(String label, bool on, VoidCallback onTap) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Semantics(
        selected: on,
        button: true,
        child: Material(
          color: on ? AppColors.gold : AppColors.surface,
          shape: StadiumBorder(
            side: BorderSide(color: on ? AppColors.gold : AppColors.hairline),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: AppText.body(
                    12,
                    color: on ? AppColors.onGold : AppColors.text,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          pill(
            allLabel ?? tr('الكل', 'All'),
            selected == null,
            () => onSelect(null),
          ),
          for (final o in options)
            pill(o, selected == o, () => onSelect(selected == o ? null : o)),
        ],
      ),
    );
  }
}

/// Showtimes grouped by format: "IMAX  [7:30] [10:45]".
class FormatRows extends StatelessWidget {
  const FormatRows({super.key, required this.showtimes});

  final List<Showtime> showtimes;

  @override
  Widget build(BuildContext context) {
    final byFormat = <String, List<Showtime>>{};
    for (final s in showtimes) {
      (byFormat[s.format] ??= []).add(s);
    }
    final groups = byFormat.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, e) in groups.indexed) ...[
          // A cinema showing the film in more than one format (IMAX and
          // Standard, say): a line between them.
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Divider(
                height: 1,
                thickness: 1,
                color: AppColors.hairline,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      shortFormat(e.key),
                      style: AppText.body(
                        11,
                        color: formatTint(e.key),
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in e.value)
                        TimeChip(
                          showtime: s,
                          onTap: () => showShowtimeSheet(context, s),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Rounded surface card used for schedule blocks.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: AppDecor.card(radius: 16),
    child: child,
  );
}

/// Round icon button on a dark translucent disc, for headers over images.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, color: color ?? AppColors.text, size: 20),
    style: IconButton.styleFrom(
      backgroundColor: AppColors.glass,
      minimumSize: const Size(44, 44),
    ),
  );
}
