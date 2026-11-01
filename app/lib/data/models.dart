/// The app's view of the scraper's output: cinemas, movies (one per film,
/// joined across chains) and showtimes pointing at both.
library;

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

  /// "VOX · City Centre Almaza" — how a showtime names its cinema.
  String get label => chain == 'Independent' ? name : '$chain · $name';

  factory Cinema.fromJson(Map<String, dynamic> j) => Cinema(
    id: j['id'] as String,
    chain: j['chain'] as String,
    name: j['name'] as String,
    nameAr: j['nameAr'] as String?,
    city: j['city'] as String?,
    area: j['area'] as String?,
    url: j['url'] as String?,
    attribution: j['attribution'] as String?,
  );
}

class Movie {
  const Movie({
    required this.id,
    required this.title,
    this.tmdbId,
    this.titleAr,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.runtime,
    this.genres = const [],
    this.fallbackPosterUrl,
  });

  final String id;
  final int? tmdbId;
  final String title;
  final String? titleAr;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final int? runtime;
  final List<String> genres;
  final String? fallbackPosterUrl;

  /// Arabic title when there is one; the app is Arabic-first.
  String get displayTitle => titleAr ?? title;

  /// Shown under the Arabic title when the two differ.
  String? get subtitle => titleAr != null ? title : null;

  String? get posterUrl => posterPath != null
      ? 'https://image.tmdb.org/t/p/w342$posterPath'
      : fallbackPosterUrl;

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
    id: j['id'] as String,
    tmdbId: j['tmdbId'] as int?,
    title: j['title'] as String,
    titleAr: j['titleAr'] as String?,
    overview: j['overview'] as String?,
    posterPath: j['posterPath'] as String?,
    backdropPath: j['backdropPath'] as String?,
    releaseDate: j['releaseDate'] as String?,
    runtime: j['runtime'] as int?,
    genres: (j['genres'] as List?)?.cast<String>() ?? const [],
    fallbackPosterUrl: j['fallbackPosterUrl'] as String?,
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
