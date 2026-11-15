/**
 * A page cut down to what a scraper reads: no <head>, scripts, styles,
 * inline SVG, comments or runs of whitespace. The cinema-fetch relay
 * (supabase/functions/cinema-fetch, which keeps its own copy of this
 * function) applies it when asked, since every byte it sends back is egress
 * on Supabase's quota. Only for pages read by their markup: Renaissance's
 * booking page keeps its scripts, which hold the hall id.
 */
export function trimHtml(html: string): string {
  return html
    .replace(/<head\b[\s\S]*?<\/head>/gi, '')
    .replace(/<(script|style|svg|noscript)\b[\s\S]*?<\/\1>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/\s+/g, ' ');
}
