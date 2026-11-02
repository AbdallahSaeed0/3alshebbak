// Cinema schedules are local Cairo time. Egypt observes DST again (since 2023),
// so the offset comes from the tz database rather than a fixed +02:00.

const TZ = 'Africa/Cairo';

/** Shows before this hour belong to the previous schedule day. */
const BUSINESS_DAY_START_HOUR = 6;

export function cairoToday(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date());
}

export function addDays(isoDate: string, days: number): string {
  const d = new Date(`${isoDate}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** "dd-mm-yyyy" → "yyyy-mm-dd". */
export function fromDmy(dmy: string): string | null {
  const m = /^(\d{2})-(\d{2})-(\d{4})$/.exec(dmy.trim());
  return m ? `${m[3]}-${m[2]}-${m[1]}` : null;
}

/** "yyyy-mm-dd" → "dd-mm-yyyy". */
export function toDmy(iso: string): string {
  const [y, m, d] = iso.split('-');
  return `${d}-${m}-${y}`;
}

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** "Wednesday 16 Dec", "Wed 16 Dec" → the next such date on or after `today` (yyyy-mm-dd); sites give no year. */
export function dayFromLabel(label: string, today: string): string | null {
  const m = /(\d{1,2})\s+([A-Za-z]{3})/.exec(label);
  const month = m ? MONTHS.indexOf(m[2].toLowerCase()) : -1;
  if (!m || month < 0) return null;
  const year = Number(today.slice(0, 4));
  const iso = (y: number) => `${y}-${String(month + 1).padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  // A day a little in the past is still this year (yesterday's late show); far back means next year.
  return iso(year) >= addDays(today, -7) ? iso(year) : iso(year + 1);
}

/**
 * elCinema lists today and the six days after. VOX and Premiere's own sites
 * only add presale days past that, so the two never list the same show.
 */
export const presaleFrom = () => addDays(cairoToday(), 7);

/** "10:30 AM", "12:30 am", "22:15" → [hours, minutes] on a 24h clock. */
export function parseClock(text: string): [number, number] | null {
  const m = /(\d{1,2}):(\d{2})\s*([AaPp][Mm])?/.exec(text);
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  const ampm = m[3]?.toLowerCase();
  if (ampm === 'pm' && h < 12) h += 12;
  if (ampm === 'am' && h === 12) h = 0;
  return h < 24 && min < 60 ? [h, min] : null;
}

function cairoOffset(isoDate: string, h: number, m: number): string {
  // Format a nearby instant in Cairo to read its offset ("GMT+02:00" / "GMT+03:00").
  const guess = new Date(`${isoDate}T${pad(h)}:${pad(m)}:00Z`);
  const name = new Intl.DateTimeFormat('en-US', { timeZone: TZ, timeZoneName: 'longOffset' })
    .formatToParts(guess)
    .find((p) => p.type === 'timeZoneName')?.value;
  const off = /GMT([+-]\d{2}:\d{2})/.exec(name ?? '');
  return off ? off[1] : '+02:00';
}

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

/**
 * Real start of a show listed under `businessDate` at `clock`. Times after
 * midnight (or explicitly flagged as such) fall on the next calendar day.
 */
export function showStart(businessDate: string, clock: string, afterMidnight = false): string | null {
  const hm = parseClock(clock);
  if (!hm) return null;
  const [h, m] = hm;
  const date = afterMidnight || h < BUSINESS_DAY_START_HOUR ? addDays(businessDate, 1) : businessDate;
  return `${date}T${pad(h)}:${pad(m)}:00${cairoOffset(date, h, m)}`;
}
