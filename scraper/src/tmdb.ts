// Joins every source's films into one catalog of movies, matched to TMDB.
// The same film is listed by up to five chains under slightly different titles
// ("Avengers: Doomsday (2D)", "AVENGERS DOOMSDAY IMAX"…); a TMDB id is what
// makes them one movie in the app.
//
// Lookups are cached in data/tmdb-cache.json, so a normal run only asks TMDB
// about films it hasn't seen this week. data/tmdb-overrides.json pins a title
// to an id (or to null: "not on TMDB") when the automatic match gets it wrong —
// typically Egyptian films listed under a transliterated title.

import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { errorMessage, fetchText, pool, sleep } from './http.js';
import type { Film } from './model.js';

const API = 'https://api.themoviedb.org/3';
const CACHE_FILE = 'data/tmdb-cache.json';
const OVERRIDES_FILE = 'data/tmdb-overrides.json';
const HIT_TTL_MS = 7 * 24 * 3600_000;
const MISS_TTL_MS = 24 * 3600_000;
const MIN_SCORE = 0.75;

export interface Movie {
  /** `tmdb:<id>`, or `local:<normalized title>` for a film TMDB doesn't know. */
  id: string;
  tmdbId: number | null;
  title: string;
  titleAr: string | null;
  originalTitle: string | null;
  overview: string | null;
  posterPath: string | null;
  backdropPath: string | null;
  releaseDate: string | null;
  runtime: number | null;
  genres: string[];
  /** TMDB's vote average out of 10, once enough people voted. */
  rating: number | null;
  /** YouTube id of the trailer. */
  trailerKey: string | null;
  /** A chain's own poster, for films with no TMDB match. */
  fallbackPosterUrl: string | null;
}

export interface Catalog {
  movies: Movie[];
  /** source film id → movie id */
  filmToMovie: Record<string, string>;
  unmatched: string[];
}

interface CacheEntry<T> { at: number; value: T }
type Cache = Record<string, CacheEntry<unknown>>;

interface TmdbSearchHit {
  id: number;
  title: string;
  original_title: string;
  release_date?: string;
  popularity: number;
}

interface TmdbDetails {
  id: number;
  title: string;
  original_title: string;
  original_language: string;
  overview: string;
  poster_path: string | null;
  backdrop_path: string | null;
  release_date: string;
  runtime: number | null;
  genres: { name: string }[];
  vote_average?: number;
  vote_count?: number;
  videos?: { results: TmdbVideo[] };
}

interface TmdbVideo {
  key: string;
  site: string;
  type: string;
  official: boolean;
  iso_639_1: string | null;
}

/** Fewer votes than this and TMDB's average says little. */
const MIN_VOTES = 20;

/**
 * The trailer to show: a YouTube trailer (a teaser if there's none), official
 * first, in the film's own language when it's Arabic.
 */
function pickTrailer(videos: TmdbVideo[], arabic: boolean): string | null {
  const score = (v: TmdbVideo) =>
    (v.type === 'Trailer' ? 4 : 0) + (v.official ? 2 : 0) + (arabic && v.iso_639_1 === 'ar' ? 1 : 0);
  const best = videos
    .filter((v) => v.site === 'YouTube' && (v.type === 'Trailer' || v.type === 'Teaser'))
    .sort((a, b) => score(b) - score(a))[0];
  return best?.key ?? null;
}

// Format and edition noise chains add to titles. Only words that can't be part
// of a real title ("Mad Max" keeps its Max); tags in brackets go separately.
const NOISE = /\b(imax|4dx|mx4d|screenx|dbox|d-box|2d|3d|infinity vision|dubbed|re-?release)\b/gi;

/** A comparable form of a title: lower case, no format tags, no punctuation. */
export function normalizeTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/\([^)]*\)|\[[^\]]*\]/g, ' ')
    .replace(NOISE, ' ')
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

/** The title to search TMDB with: format tags removed, punctuation kept. */
function searchQuery(title: string): string {
  return title.replace(/\([^)]*\)|\[[^\]]*\]/g, ' ').replace(NOISE, ' ').replace(/\s+/g, ' ').replace(/[\s:,-]+$/, '').trim();
}

export function similarity(a: string, b: string): number {
  if (a === b) return 1;
  if (a && b && (a.startsWith(b) || b.startsWith(a))) return 0.8;
  const ta = new Set(a.split(' '));
  const tb = new Set(b.split(' '));
  const common = [...ta].filter((t) => tb.has(t)).length;
  return common / Math.max(ta.size, tb.size, 1);
}

/** Films in cinemas now came out recently or are about to. */
function recency(releaseDate: string | undefined): number {
  if (!releaseDate) return 0;
  const months = (Date.now() - Date.parse(releaseDate)) / (30 * 24 * 3600_000);
  if (months >= -6 && months <= 18) return 0.25;
  // Old films do come back (re-releases, classics nights), so this is a nudge, not a rule.
  return 0;
}

class Tmdb {
  private cache: Cache = {};
  private overrides: Record<string, number | null> = {};

  constructor(private auth: { key?: string; token?: string }) {}

  static fromEnv(): Tmdb | null {
    const key = process.env.TMDB_API_KEY;
    const token = process.env.TMDB_READ_TOKEN;
    return key || token ? new Tmdb({ key, token }) : null;
  }

  async load() {
    this.cache = await readJson(CACHE_FILE, {});
    this.overrides = await readJson(OVERRIDES_FILE, {});
  }

  async save() {
    await mkdir('data', { recursive: true });
    await writeFile(CACHE_FILE, JSON.stringify(this.cache));
  }

  override(normalized: string): number | null | undefined {
    return normalized in this.overrides ? this.overrides[normalized] : undefined;
  }

  private async get<T>(path: string, params: Record<string, string>): Promise<T> {
    const url = new URL(API + path);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    if (this.auth.key && !this.auth.token) url.searchParams.set('api_key', this.auth.key);
    const res = await fetch(url, {
      headers: this.auth.token ? { Authorization: `Bearer ${this.auth.token}` } : {},
      signal: AbortSignal.timeout(15_000),
    });
    if (res.status === 429) {
      await new Promise((r) => setTimeout(r, 2000));
      return this.get(path, params);
    }
    if (!res.ok) throw new Error(`TMDB ${path}: HTTP ${res.status}`);
    return (await res.json()) as T;
  }

  private async cached<T>(key: string, fetcher: () => Promise<T>, isHit: (v: T) => boolean): Promise<T> {
    const entry = this.cache[key] as CacheEntry<T> | undefined;
    if (entry && Date.now() - entry.at < (isHit(entry.value) ? HIT_TTL_MS : MISS_TTL_MS)) return entry.value;
    const value = await fetcher();
    this.cache[key] = { at: Date.now(), value };
    return value;
  }

  /** Best TMDB id for a title, or null when nothing scores high enough. */
  async search(title: string): Promise<number | null> {
    const query = searchQuery(title);
    const want = normalizeTitle(title);
    return this.cached(
      `search:${want}`,
      async () => {
        const { results } = await this.get<{ results: TmdbSearchHit[] }>('/search/movie', {
          query,
          include_adult: 'false',
          language: /\p{Script=Arabic}/u.test(query) ? 'ar-EG' : 'en-US',
        });
        let best: { id: number; score: number } | null = null;
        for (const hit of results.slice(0, 10)) {
          const sim = Math.max(similarity(want, normalizeTitle(hit.title)), similarity(want, normalizeTitle(hit.original_title)));
          const score = sim + recency(hit.release_date) + Math.min(hit.popularity, 100) / 2000;
          if (sim >= 0.6 && (!best || score > best.score)) best = { id: hit.id, score };
        }
        return best && best.score >= MIN_SCORE ? best.id : null;
      },
      (v) => v != null,
    );
  }

  /**
   * A film's running time from its elCinema page ("90 minutes"), for films
   * TMDB has no runtime for yet — new Egyptian releases, mostly. Cached like
   * TMDB lookups, so each page is read about once a week.
   */
  async elcinemaRuntime(url: string): Promise<number | null> {
    return this.cached(
      `elcinema-runtime:${url}`,
      async () => {
        await sleep(1500); // elCinema's pages are its product: one at a time, slowly.
        const page = await fetchText(url, 1);
        const mins = Number(/(\d{2,3})\s*minutes/i.exec(page.replace(/<[^>]*>/g, ' '))?.[1]);
        return mins >= 30 && mins <= 300 ? mins : null;
      },
      (v) => v != null,
    );
  }

  async details(id: number): Promise<{ en: TmdbDetails; arTitle: string | null; trailerKey: string | null }> {
    const { en, ar } = await this.cached(
      // v2: with the rating and videos.
      `movie-en-ar-v2:${id}`,
      async () => ({
        en: await this.get<TmdbDetails>(`/movie/${id}`, {
          language: 'en-US',
          append_to_response: 'videos',
          include_video_language: 'ar,en,null',
        }),
        ar: await this.get<TmdbDetails>(`/movie/${id}`, { language: 'ar-EG' }),
      }),
      () => true,
    );
    // With no Arabic translation TMDB falls back to the original title — which
    // for a Kurdish or Persian film is in Arabic script but isn't Arabic.
    const untranslated = ar.title === ar.original_title && ar.original_language !== 'ar';
    const arTitle =
      ar.title && ar.title !== en.title && !untranslated && /\p{Script=Arabic}/u.test(ar.title) ? ar.title : null;
    const trailerKey = pickTrailer(en.videos?.results ?? [], en.original_language === 'ar');
    return { en, arTitle, trailerKey };
  }
}

async function readJson<T>(path: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await readFile(path, 'utf8')) as T;
  } catch {
    return fallback;
  }
}

function localMovie(normalized: string, film: Film): Movie {
  return {
    id: `local:${normalized.replace(/ /g, '-') || createHash('sha1').update(film.id).digest('hex').slice(0, 12)}`,
    tmdbId: null,
    title: searchQuery(film.title) || film.title,
    titleAr: /\p{Script=Arabic}/u.test(film.title) ? film.title : null,
    originalTitle: null,
    overview: null,
    posterPath: null,
    backdropPath: null,
    releaseDate: null,
    runtime: film.durationMins ?? null,
    genres: film.genres ? film.genres.split(/\s*[,|]\s*/).filter(Boolean) : [],
    rating: null,
    trailerKey: null,
    fallbackPosterUrl: film.posterUrl ?? null,
  };
}

/**
 * Matches every source film to a movie. Without TMDB credentials, films are
 * still joined by normalized title so the rest of the pipeline works.
 */
export async function buildCatalog(films: Film[], log: (m: string) => void = () => {}): Promise<Catalog> {
  const tmdb = Tmdb.fromEnv();
  if (!tmdb) log('TMDB_API_KEY / TMDB_READ_TOKEN not set: joining films by title only');
  await tmdb?.load();

  // One lookup per distinct title, however many chains list it.
  const byTitle = new Map<string, Film[]>();
  for (const f of films) {
    const key = normalizeTitle(f.title);
    byTitle.set(key, [...(byTitle.get(key) ?? []), f]);
  }

  const movies = new Map<string, Movie>();
  const filmToMovie: Record<string, string> = {};
  const unmatched: string[] = [];

  await pool([...byTitle.entries()], 4, async ([normalized, group]) => {
    let tmdbId: number | null = null;
    if (tmdb) {
      try {
        const pinned = tmdb.override(normalized);
        tmdbId = pinned !== undefined ? pinned : await tmdb.search(group[0].title);
        if (tmdbId != null && !movies.has(`tmdb:${tmdbId}`)) {
          const { en, arTitle, trailerKey } = await tmdb.details(tmdbId);
          movies.set(`tmdb:${tmdbId}`, {
            id: `tmdb:${tmdbId}`,
            tmdbId,
            title: en.title,
            titleAr: arTitle,
            originalTitle: en.original_title !== en.title ? en.original_title : null,
            overview: en.overview || null,
            posterPath: en.poster_path,
            backdropPath: en.backdrop_path,
            releaseDate: en.release_date || null,
            runtime: en.runtime || null,
            genres: en.genres.map((g) => g.name),
            rating: (en.vote_count ?? 0) >= MIN_VOTES && en.vote_average ? Math.round(en.vote_average * 10) / 10 : null,
            trailerKey,
            fallbackPosterUrl: group.find((f) => f.posterUrl)?.posterUrl ?? null,
          });
        }
      } catch (e) {
        log(`TMDB "${group[0].title}": ${errorMessage(e)}`);
        tmdbId = null;
      }
    }
    let movieId: string;
    if (tmdbId != null && movies.has(`tmdb:${tmdbId}`)) {
      movieId = `tmdb:${tmdbId}`;
    } else {
      const local = localMovie(normalized, group[0]);
      movieId = local.id;
      if (!movies.has(movieId)) movies.set(movieId, local);
      unmatched.push(group[0].title);
    }
    for (const f of group) filmToMovie[f.id] = movieId;
  });

  // TMDB often has no runtime for a new local release; elCinema's page does.
  if (tmdb) {
    for (const movie of movies.values()) {
      if (movie.runtime) continue;
      const page = films.find((f) => filmToMovie[f.id] === movie.id && /elcinema\.com\/(en\/)?work\/\d+/.test(f.url ?? ''))?.url;
      if (!page) continue;
      try {
        movie.runtime = await tmdb.elcinemaRuntime(page);
      } catch (e) {
        log(`elCinema runtime "${movie.title}": ${errorMessage(e)}`);
      }
    }
  }

  await tmdb?.save();
  return { movies: [...movies.values()], filmToMovie, unmatched: unmatched.sort() };
}
