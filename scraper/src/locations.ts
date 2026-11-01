// Puts each cinema on the map: coordinates (and the city/area when the chain's
// site doesn't say) from data/cinema-locations.json. That file is kept by hand;
// scripts/geocode-cinemas.ts fills in new cinemas from OpenStreetMap.

import { readFileSync } from 'node:fs';
import type { ScrapeResult } from './model.js';

type Location = { lat: number; lng: number; city: string; area?: string; approximate?: boolean };

const locations: Record<string, Location> = JSON.parse(
  readFileSync(new URL('../data/cinema-locations.json', import.meta.url), 'utf8'),
);

export function placeCinemas(result: ScrapeResult): ScrapeResult {
  for (const c of result.cinemas) {
    const at = locations[c.id];
    if (!at) {
      const warning = `${c.id}: no map location — add it to data/cinema-locations.json`;
      if (!result.warnings.includes(warning)) result.warnings.push(warning);
      continue;
    }
    c.lat = at.lat;
    c.lng = at.lng;
    c.city ??= at.city;
    c.area ??= at.area;
    if (at.approximate) c.locationApproximate = true;
  }
  return result;
}
