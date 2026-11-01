// One-time helper: looks up each cinema's coordinates on OpenStreetMap
// (Nominatim) and writes data/cinema-locations.json. That file is the source
// of truth afterwards — fix a wrong pin by hand there, not by re-running.
// Only cinemas missing from the file are looked up. Nominatim's policy: at
// most one request a second, an identifying User-Agent.
//
//   npx tsx scripts/geocode-cinemas.ts

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

type Location = { lat: number; lng: number; city: string; area?: string; query?: string; approximate?: boolean };

const FILE = new URL('../data/cinema-locations.json', import.meta.url);

/** Cinema id → [search query, city, area]. Queries name the mall the cinema is in. */
const QUERIES: Record<string, [string, string, string?]> = {
  'renaissance:san_stephano': ['San Stefano Grand Plaza, Alexandria', 'Alexandria', 'San Stefano'],
  'renaissance:al_rehab': ['Rehab Mall 1, New Cairo', 'Cairo', 'Rehab City'],
  'renaissance:downtown': ['Emad El Din Street, Cairo', 'Cairo', 'Downtown'],
  'renaissance:dandy_mall': ['Dandy Mega Mall', 'Cairo', '6th of October'],
  'renaissance:semoha': ['Smouha, Alexandria', 'Alexandria', 'Smouha'],
  'renaissance:madinty': ['Open Air Mall, Madinaty', 'Cairo', 'Madinaty'],
  'renaissance:banha': ['Banha', 'Banha'],
  'renaissance:al-masrya-plaza-agazig': ['Zagazig', 'Zagazig'],
  'scene:cfc': ['Cairo Festival City Mall', 'Cairo', 'New Cairo'],
  'scene:district5': ['District 5, New Cairo', 'Cairo', 'New Cairo'],
  'premiere:nile-cinema': ['Nile City Towers, Cairo', 'Cairo', 'Corniche'],
  'premiere:premiere-plaza': ['Plaza Mall, Sheikh Zayed', 'Cairo', 'Sheikh Zayed'],
  'premiere:galaxy-elmanial': ['Galaxy Cinema, Manial', 'Cairo', 'Manial'],
  'premiere:premiere-point90': ['Point 90 Mall', 'Cairo', 'New Cairo'],
  'premiere:cima-arkan': ['Arkan Plaza, Sheikh Zayed', 'Cairo', 'Sheikh Zayed'],
  'elcinema:city-centre-almaza': ['City Centre Almaza', 'Cairo', 'Heliopolis'],
  'elcinema:mall-of-egypt': ['Mall of Egypt', 'Cairo', '6th of October'],
  'elcinema:city-centre-alexandria': ['City Centre Alexandria', 'Alexandria', 'Moharam Bek'],
  'elcinema:americana-plaza': ['Americana Plaza, Sheikh Zayed', 'Cairo', 'Sheikh Zayed'],
  'elcinema:galaxy-el-maadi': ['Galaxy Cinema, Maadi', 'Cairo', 'Maadi'],
  'elcinema:galaxy-cineplex-mall-of-arabia': ['Mall of Arabia, 6th of October', 'Cairo', '6th of October'],
  'elcinema:galaxy-el-gezeera-plaza': ['Gezira Plaza, Mansoura', 'Mansoura'],
  'elcinema:galaxy-mall-of-university': ['Mansoura University', 'Mansoura'],
  'elcinema:galaxy-mega': ['Sohag', 'Sohag', 'New Sohag'],
  'elcinema:sea-cinema-amir': ['Amir Cinema, Alexandria', 'Alexandria', 'Downtown'],
  'elcinema:sea-cinema-royal-plaza': ['Royal Plaza, Alexandria', 'Alexandria', 'Montazah'],
  'elcinema:sea-cinema-arabella': ['Arabella Plaza, New Cairo', 'Cairo', 'New Cairo'],
  'elcinema:sea-cinema-tanta': ['Tanta', 'Tanta'],
  'elcinema:sea-cinema-el-gouna': ['El Gouna', 'Hurghada', 'El Gouna'],
  'elcinema:sea-cinema-shebin-el-kom': ['Shebin El Kom', 'Shebin El Kom'],
  'elcinema:sea-cinema-fayoum': ['Faiyum', 'Fayoum'],
  'elcinema:sea-cinema-luxor': ['Luxor', 'Luxor'],
  'elcinema:city-stars-cinema': ['City Stars, Nasr City', 'Cairo', 'Nasr City'],
  'elcinema:golden-stars': ['City Stars, Nasr City', 'Cairo', 'Nasr City'],
  'elcinema:sun-city': ['Sun City Mall, Heliopolis', 'Cairo', 'Heliopolis'],
  'elcinema:cine-max': ['Hyper One, Sheikh Zayed', 'Cairo', 'Sheikh Zayed'],
  'elcinema:cine-max-minya': ['Minya', 'Minya'],
  'elcinema:diamond-bandar-maadi': ['Bandar Mall, Maadi', 'Cairo', 'Maadi'],
  'elcinema:diamond-marseille-park': ['Montaza, Alexandria', 'Alexandria', 'Montazah'],
  'elcinema:cairo-metro': ['Metro Cinema, Talaat Harb, Cairo', 'Cairo', 'Downtown'],
  'elcinema:alexandria-metro': ['Metro Cinema, Alexandria', 'Alexandria', 'Downtown'],
  'elcinema:donia-porto-el-sokhna': ['Porto Sokhna', 'Ain Sokhna', 'Ain Sokhna'],
  'elcinema:almasa-matrouh': ['Marsa Matruh', 'Marsa Matrouh'],
  'elcinema:zawya': ['Zawya Cinema, Cairo', 'Cairo', 'Downtown'],
  'elcinema:zamalek-cinema': ['Zamalek Cinema, Cairo', 'Cairo', 'Zamalek'],
  'elcinema:el-tahrir-cinema': ['Tahrir Cinema, Dokki', 'Cairo', 'Dokki'],
  'elcinema:cosmos-cinema': ['Cosmos Cinema, Emad El Din, Cairo', 'Cairo', 'Downtown'],
  'elcinema:lido-cinema': ['Lido Cinema, Cairo', 'Cairo', 'Downtown'],
  'elcinema:universal-cinema': ['New Cairo', 'Cairo', 'New Cairo'],
  'elcinema:golf-city-cinema': ['Golf City Mall, Obour', 'Cairo', 'Obour City'],
  'elcinema:grand-nile-tower-cinema': ['Grand Nile Tower, Cairo', 'Cairo', 'Garden City'],
  'elcinema:cairo-mall-cinema': ['Cairo Mall, Haram', 'Cairo', 'Haram'],
  'elcinema:green-plaza-cinema': ['Green Plaza, Alexandria', 'Alexandria', 'Smouha'],
  'elcinema:deeb-mall-cinema': ['Roushdy, Alexandria', 'Alexandria', 'Roshdy'],
  'elcinema:agamy-star-cinema': ['Agami, Alexandria', 'Alexandria', 'Agamy'],
  'elcinema:tulip-of-alexandria-cinema': ['Tolip Hotel Alexandria', 'Alexandria'],
  'elcinema:white-rose-cinema': ['Montaza, Alexandria', 'Alexandria', 'Montazah'],
  'elcinema:grand-hurghada-cinema': ['Hurghada', 'Hurghada'],
  'elcinema:kiroseiz-sharm-el-sheikh': ['Sharm El Sheikh', 'Sharm El Sheikh'],
  'elcinema:horeya-cinema': ['Ismailia', 'Ismailia', 'Downtown'],
  'elcinema:sea-way-suez-cinema': ['Port Tawfik, Suez', 'Suez', 'Port Tawfik'],
  'elcinema:cinematy-port-said': ['Port Said', 'Port Said'],
  'elcinema:el-shams-cinema': ['Ain Shams, Cairo', 'Cairo', 'Ain Shams'],
};

/** A query that only names a city or district gives an approximate pin. */
const APPROXIMATE = /^(Banha|Zagazig|Sohag|Tanta|El Gouna|Shebin El Kom|Faiyum|Luxor|Minya|Marsa Matruh|New Cairo|Hurghada|Sharm El Sheikh|Ismailia|Port Said|Smouha, Alexandria|Agami, Alexandria|Roushdy, Alexandria|Montaza, Alexandria|Ain Shams, Cairo|Mansoura University)$/;

const locations: Record<string, Location> = existsSync(FILE) ? JSON.parse(readFileSync(FILE, 'utf8')) : {};

for (const [id, [query, city, area]] of Object.entries(QUERIES)) {
  if (locations[id]) continue;
  const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=eg&q=${encodeURIComponent(query)}`;
  const res = await fetch(url, { headers: { 'User-Agent': '3alShebbakBot/0.1 (one-time cinema geocoding)' } });
  const [hit] = (await res.json()) as { lat: string; lon: string; display_name: string }[];
  if (hit) {
    locations[id] = {
      lat: +(+hit.lat).toFixed(5),
      lng: +(+hit.lon).toFixed(5),
      city,
      ...(area ? { area } : {}),
      query,
      ...(APPROXIMATE.test(query) ? { approximate: true } : {}),
    };
    console.log(`${id}: ${hit.display_name}`);
  } else {
    console.log(`${id}: NOT FOUND (${query})`);
  }
  await new Promise((r) => setTimeout(r, 1100));
}

writeFileSync(FILE, JSON.stringify(locations, null, 2) + '\n');
