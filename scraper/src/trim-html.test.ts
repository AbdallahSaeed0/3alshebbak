import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { trimHtml } from './trim-html.js';

test('a page keeps its markup and loses scripts, styles and the head', () => {
  const page = `<html><head><title>x</title><script>var a = 1;</script></head>
    <body><style>.a{}</style><!-- note --><svg><path/></svg>
    <a class="js-booking-confirm-link" data-event-time="10:30 AM">  10:30  </a><script src="x.js"></script></body></html>`;
  assert.equal(
    trimHtml(page),
    '<html> <body> <a class="js-booking-confirm-link" data-event-time="10:30 AM"> 10:30 </a></body></html>',
  );
});

test("the relay's copy is the same code", () => {
  const relay = readFileSync('supabase/functions/cinema-fetch/index.ts', 'utf8');
  for (const line of readFileSync('src/trim-html.ts', 'utf8').match(/\.replace\(.*\)/g)!) {
    assert.ok(relay.includes(line.trim()), line);
  }
});
