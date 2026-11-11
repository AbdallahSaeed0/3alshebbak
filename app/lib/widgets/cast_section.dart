import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../theme.dart';
import '../util/i18n.dart';
import 'common.dart';

/// The film page's cast: who directed it, then the billed cast in a row you
/// swipe through. Tapping an actor shows their part and the other films
/// they're in that are showing now.
class CastSection extends StatelessWidget {
  const CastSection({
    super.key,
    required this.movie,
    required this.credits,
    required this.onFilm,
  });

  final Movie movie;
  final Credits credits;

  /// Opens another film's page.
  final void Function(Movie) onFilm;

  @override
  Widget build(BuildContext context) {
    final cast = credits.cast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('الممثلين', 'Cast'), style: AppText.display(22)),
        if (credits.directors.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '${tr('إخراج', 'Directed by')}: ${credits.directors.join(tr('، ', ', '))}',
            style: AppText.body(13, color: AppColors.muted),
          ),
        ],
        if (cast.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _Actor(
                person: cast[i],
                onTap: () => _showActor(context, cast[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showActor(BuildContext context, CastMember person) {
    final catalog = AppScope.of(context).catalog;
    // The same name in another film's billed cast: TMDB spells each person
    // one way, so the name is enough.
    final others = [
      for (final m in catalog.movies.values)
        if (m.id != movie.id &&
            (m.credits?.cast.any((p) => p.name == person.name) ?? false))
          m,
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Face(person: person, size: 72),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          textDirection: TextDirection.ltr,
                          style: AppText.display(22),
                        ),
                        if (person.character != null)
                          Text(
                            '${tr('في دور', 'as')} ${person.character}',
                            style: AppText.body(14, color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  tr('كمان في السينما دلوقتي', 'Also showing now'),
                  style: AppText.body(14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: others.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () {
                        Navigator.of(sheet).pop();
                        onFilm(others[i]);
                      },
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            Poster(
                              movie: others[i],
                              width: 72,
                              height: 104,
                              radius: 8,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              others[i].displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Actor extends StatelessWidget {
  const _Actor({required this.person, required this.onTap});

  final CastMember person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      width: 76,
      child: Column(
        children: [
          _Face(person: person, size: 68),
          const SizedBox(height: 6),
          Text(
            person.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(12, weight: FontWeight.w700).copyWith(
              height: 1.25,
            ),
          ),
          if (person.character != null)
            Text(
              person.character!,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(10.5, color: AppColors.muted),
            ),
        ],
      ),
    ),
  );
}

/// A round photo, or the person's initial when TMDB has none.
class _Face extends StatelessWidget {
  const _Face({required this.person, required this.size});

  final CastMember person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = Container(
      color: AppColors.raised,
      alignment: Alignment.center,
      child: Text(
        person.name.characters.first.toUpperCase(),
        style: AppText.display(size * 0.4, color: AppColors.muted),
      ),
    );
    final url = person.photoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.perforation),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? initial
          : Image.network(
              url,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) => initial,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : initial,
            ),
    );
  }
}
