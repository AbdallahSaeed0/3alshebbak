// A source can know the hall of shows another source lists (model.ts
// hallHints): Premiere's site names the hall of every show, elCinema, which
// lists the week at Premiere Plaza, Point90 and Cima Arkan, doesn't. The two
// list films under their own ids, so shows are matched once both are movies.

import type { ScrapeResult } from './model.js';

/**
 * Puts each hint's hall on the show at the same cinema, movie and start that
 * has none. A start where the hints disagree (one film in two halls at once)
 * is left alone. Returns how many shows got a hall.
 */
export function applyHallHints(results: ScrapeResult[], filmToMovie: Record<string, string>): number {
  const halls = new Map<string, string | null>();
  for (const h of results.flatMap((r) => r.hallHints ?? [])) {
    const movie = filmToMovie[h.filmId];
    if (!movie) continue;
    const key = `${h.cinemaId}|${movie}|${Date.parse(h.start)}`;
    const seen = halls.get(key);
    halls.set(key, seen === undefined || seen === h.hall ? h.hall : null);
  }
  let applied = 0;
  for (const r of results) {
    for (const s of r.showtimes) {
      if (s.hall) continue;
      const hall = halls.get(`${s.cinemaId}|${filmToMovie[s.filmId]}|${Date.parse(s.start)}`);
      if (hall) {
        s.hall = hall;
        applied++;
      }
    }
  }
  return applied;
}
