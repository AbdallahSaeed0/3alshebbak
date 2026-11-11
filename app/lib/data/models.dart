/// The app's view of the scraper's output: cinemas, movies (one per film,
/// joined across chains) and showtimes pointing at both.
library;

import '../util/i18n.dart';

class Cinema {
  const Cinema({
    required this.id,
    required this.chain,
    required this.name,
    this.nameAr,
    this.city,
    this.area,
    this.url,
    this.attribution,
    this.lat,
    this.lng,
    this.locationApproximate = false,
  });

  final String id;
  final String chain;
  final String name;
  final String? nameAr;
  final String? city;
  final String? area;
  final String? url;

  /// Third-party data source to credit, e.g. "elCinema.com".
  final String? attribution;

  /// Map pin. [locationApproximate]: the mall's or the town's, not the door's.
  final double? lat;
  final double? lng;
  final bool locationApproximate;

  bool get hasLocation => lat != null && lng != null;

  /// How a showtime names its cinema: "VOX · City Centre Almaza", or in
  /// Arabic "سينما فوكس سيتي سنتر ألماظة". elCinema's Arabic names already
  /// say the chain; the chains' own sites give just the branch ("وسط البلد").
  String get label {
    if (!Lang.english && nameAr != null) {
      return id.startsWith('elcinema:')
          ? nameAr!
          : '${_chainsAr[chain] ?? chain} · $nameAr';
    }
    return chain == 'Independent' ? name : '$chain · $name';
  }

  static const _chainsAr = {
    'Renaissance': 'رينيسانس',
    'Scene': 'سين',
    'Premiere': 'بريمير',
    'VOX': 'ڤوكس',
  };

  factory Cinema.fromJson(Map<String, dynamic> j) => Cinema(
    id: j['id'] as String,
    chain: j['chain'] as String,
    name: j['name'] as String,
    nameAr: j['nameAr'] as String?,
    city: j['city'] as String?,
    area: j['area'] as String?,
    url: j['url'] as String?,
    attribution: j['attribution'] as String?,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
    locationApproximate: j['locationApproximate'] as bool? ?? false,
  );
}

class Movie {
  const Movie({
    required this.id,
    required this.title,
    this.tmdbId,
    this.titleAr,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.runtime,
    this.genres = const [],
    this.rating,
    this.trailerKey,
    this.fallbackPosterUrl,
    this.credits,
  });

  final String id;
  final int? tmdbId;
  final String title;
  final String? titleAr;

  /// TMDB's original title, when it differs from [title].
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final int? runtime;
  final List<String> genres;

  /// TMDB's vote average out of 10, once enough people voted.
  final double? rating;

  /// YouTube id of the trailer.
  final String? trailerKey;
  final String? fallbackPosterUrl;

  /// Who's in it and who directed it, when TMDB knows.
  final Credits? credits;

  String? get trailerUrl =>
      trailerKey == null ? null : 'https://www.youtube.com/watch?v=$trailerKey';

  /// Made in Arabic: its original title is written in Arabic letters. Films
  /// TMDB doesn't know only have the chain's title, Arabic when it's Arabic.
  bool get isArabic {
    final original = originalTitle ?? (tmdbId == null ? titleAr ?? '' : title);
    return _arabicLetters.hasMatch(original) &&
        !_otherScriptLetters.hasMatch(original);
  }

  static final _arabicLetters = RegExp(r'[ء-ي]');

  /// Letters Persian, Kurdish and Urdu add (پ ژ ک ی ە…): a Kurdish title is
  /// in Arabic script but the film isn't Arabic.
  static final _otherScriptLetters = RegExp(r'[پ-ۿ]');

  /// In Arabic, Arabic films by their Arabic title and foreign films by
  /// their English one — the name on the cinema's poster. In English,
  /// everything by its English title.
  String get displayTitle =>
      _arabicFirst ? titleAr ?? originalTitle ?? title : title;

  bool get _arabicFirst => isArabic && !Lang.english;

  String? get posterUrl => posterPath != null
      ? 'https://image.tmdb.org/t/p/w342$posterPath'
      : fallbackPosterUrl;

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
    id: j['id'] as String,
    tmdbId: j['tmdbId'] as int?,
    title: j['title'] as String,
    titleAr: j['titleAr'] as String?,
    originalTitle: j['originalTitle'] as String?,
    overview: j['overview'] as String?,
    posterPath: j['posterPath'] as String?,
    backdropPath: j['backdropPath'] as String?,
    releaseDate: j['releaseDate'] as String?,
    runtime: j['runtime'] as int?,
    genres: (j['genres'] as List?)?.cast<String>() ?? const [],
    rating: (j['rating'] as num?)?.toDouble(),
    trailerKey: j['trailerKey'] as String?,
    fallbackPosterUrl: j['fallbackPosterUrl'] as String?,
    credits: Credits.fromJson(j['credits']),
  );
}

/// One actor in a film's billed cast.
class CastMember {
  const CastMember({required this.name, this.character, this.photoPath});

  final String name;

  /// The part they play, as TMDB lists it.
  final String? character;
  final String? photoPath;

  String? get photoUrl =>
      photoPath == null ? null : 'https://image.tmdb.org/t/p/w185$photoPath';
}

/// A film's billed cast and directors (scraper/src/tmdb.ts, Credits).
class Credits {
  const Credits({this.cast = const [], this.directors = const []});

  final List<CastMember> cast;
  final List<String> directors;

  /// Null for no credits, or anything that isn't credits.
  static Credits? fromJson(Object? j) {
    if (j is! Map) return null;
    final cast = [
      for (final p in (j['cast'] as List?) ?? const [])
        if (p is Map && p['n'] is String)
          CastMember(
            name: p['n'] as String,
            character: p['c'] as String?,
            photoPath: p['p'] as String?,
          ),
    ];
    final directors = [
      for (final d in (j['dir'] as List?) ?? const [])
        if (d is String) d,
    ];
    if (cast.isEmpty && directors.isEmpty) return null;
    return Credits(cast: cast, directors: directors);
  }
}

/// One film's news in one alerts run: what notifications said, for anyone
/// whose films and cinemas match (scraper/src/snapshot.ts, collectNews).
class RecentNews {
  const RecentNews({
    required this.at,
    required this.movieId,
    required this.kind,
    required this.cinemas,
    this.since,
    this.shows = const {},
  });

  final DateTime at;
  final DateTime? since;
  final String movieId;

  /// 'opened', 'days' or 'shows'.
  final String kind;
  final List<String> cinemas;

  /// The new shows themselves, when the pipeline attached them: cinema →
  /// start times.
  final Map<String, List<DateTime>> shows;

  static RecentNews fromJson(Map<String, dynamic> j) => RecentNews(
    at: DateTime.parse(j['at'] as String),
    since: j['since'] == null ? null : DateTime.parse(j['since'] as String),
    movieId: j['m'] as String,
    kind: j['k'] as String,
    cinemas: (j['c'] as List).cast<String>(),
    shows: {
      for (final e in (j['s'] as Map<String, dynamic>? ?? const {}).entries)
        e.key: [
          for (final m in e.value as List)
            DateTime.fromMillisecondsSinceEpoch(
              (m as num).toInt() * 60000,
              isUtc: true,
            ),
        ],
    },
  );
}

class Showtime {
  const Showtime({
    required this.cinemaId,
    required this.movieId,
    required this.businessDate,
    required this.startsAt,
    required this.wallClock,
    required this.format,
    this.bookingUrl,
    this.priceEgp,
  });

  final String cinemaId;
  final String movieId;

  /// The schedule day the cinema lists it under ("2026-11-01"); a 12:30 AM
  /// show belongs to the day before it starts.
  final String businessDate;

  /// The real instant, for comparing with now.
  final DateTime startsAt;

  /// Cairo wall-clock time, for display — independent of the phone's time zone.
  final DateTime wallClock;

  final String format;
  final String? bookingUrl;
  final int? priceEgp;

  /// [start] is ISO 8601 with Cairo's offset, e.g. "2026-11-01T19:30:00+02:00".
  factory Showtime.fromJson(Map<String, dynamic> j, String movieId) {
    final start = j['start'] as String;
    return Showtime(
      cinemaId: j['cinemaId'] as String,
      movieId: movieId,
      businessDate: j['businessDate'] as String,
      startsAt: DateTime.parse(start),
      wallClock: DateTime.parse(start.substring(0, 19)),
      format: j['format'] as String,
      bookingUrl: j['bookingUrl'] as String?,
      priceEgp: j['priceEgp'] as int?,
    );
  }
}
