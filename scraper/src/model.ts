// The one shape every source returns. Later stages (TMDB matching, venue
// merging, Supabase) only ever see this, never a chain's own markup.

export type SourceId = 'vox' | 'premiere' | 'renaissance' | 'scene' | 'elcinema' | 'elcinema-presales';

export interface Cinema {
  /** `${source}:${slug}` — stable across runs. */
  id: string;
  source: SourceId;
  chain: string;
  name: string;
  nameAr?: string;
  city?: string;
  area?: string;
  address?: string;
  url?: string;
  /** Shown in the app when the data comes from a third party, e.g. "elCinema.com". */
  attribution?: string;
  /** Map pin, from data/cinema-locations.json (see locations.ts). */
  lat?: number;
  lng?: number;
  /** The pin is the mall's or the town's, not the cinema's own entrance. */
  locationApproximate?: boolean;
}

export interface Film {
  /** `${source}:${slug}` — each chain has its own ids; TMDB matching joins them later. */
  id: string;
  source: SourceId;
  title: string;
  url?: string;
  posterUrl?: string;
  genres?: string;
  classification?: string;
  language?: string;
  durationMins?: number;
}

export interface Showtime {
  cinemaId: string;
  filmId: string;
  /** The cinema's schedule day (yyyy-mm-dd). A 12:30 AM show belongs to the day before it starts. */
  businessDate: string;
  /** Real start time, ISO 8601 with Cairo's offset. */
  start: string;
  /** Hall type and experience as the chain names them, e.g. "IMAX", "Regular · 3D", "ScreenX". */
  format: string;
  /** Deep link to this exact show on the chain's own site, when it has one. */
  bookingUrl?: string;
  priceEgp?: number;
  /**
   * The hall the show is in, when the source says: "elcinema:<screen id>"
   * (elCinema's booking lookup), "rns:<last 6 of screen id>" (Renaissance's
   * booking data) or "prm:<cinema id>:<screen id>" (Premiere's show data). The
   * app matches it to a recorded hall plan (data/halls.json,
   * elcinemaScreenId / rnsScreenId / premiereScreenId).
   */
  hall?: string;
}

export interface ScrapeResult {
  source: SourceId;
  fetchedAt: string;
  cinemas: Cinema[];
  films: Film[];
  showtimes: Showtime[];
  /** Pages that failed while the rest of the run went on. */
  warnings: string[];
}

export interface Source {
  id: SourceId;
  scrape(): Promise<ScrapeResult>;
}

/** Collects one run's records, de-duplicating cinemas and films by id. */
export class ResultBuilder {
  private cinemas = new Map<string, Cinema>();
  private films = new Map<string, Film>();
  private showtimes = new Map<string, Showtime>();
  readonly warnings: string[] = [];

  constructor(readonly source: SourceId) {}

  cinema(c: Omit<Cinema, 'id' | 'source'> & { slug: string }): string {
    const id = `${this.source}:${c.slug}`;
    const { slug: _slug, ...rest } = c;
    this.cinemas.set(id, { ...this.cinemas.get(id), ...rest, id, source: this.source });
    return id;
  }

  film(f: Omit<Film, 'id' | 'source'> & { slug: string }): string {
    const id = `${this.source}:${f.slug}`;
    const { slug: _slug, ...rest } = f;
    const prev = this.films.get(id);
    // Keep fields an earlier page filled in and this one doesn't have.
    const merged = { ...prev, ...Object.fromEntries(Object.entries(rest).filter(([, v]) => v != null && v !== '')) };
    this.films.set(id, { ...merged, title: merged.title ?? f.title, id, source: this.source } as Film);
    return id;
  }

  showtime(s: Showtime) {
    this.showtimes.set(`${s.cinemaId}|${s.filmId}|${s.start}|${s.format}`, s);
  }

  warn(message: string) {
    this.warnings.push(message);
  }

  build(): ScrapeResult {
    return {
      source: this.source,
      fetchedAt: new Date().toISOString(),
      cinemas: [...this.cinemas.values()],
      films: [...this.films.values()],
      showtimes: [...this.showtimes.values()].sort((a, b) => a.start.localeCompare(b.start)),
      warnings: this.warnings,
    };
  }
}
