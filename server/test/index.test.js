import assert from 'node:assert/strict';
import { test } from 'node:test';

import worker, { sweep } from '../src/index.js';

const DAY = 24 * 60 * 60 * 1000;

/// Minimal in-memory R2 bucket (the calls the worker makes).
class FakeBucket {
  constructor() {
    this.objects = new Map();
  }
  async put(key, body, opts) {
    const bytes = new Uint8Array(await new Response(body).arrayBuffer());
    this.objects.set(key, { bytes, customMetadata: opts?.customMetadata ?? {}, httpEtag: '"e"' });
  }
  async head(key) {
    const o = this.objects.get(key);
    return o ? { size: o.bytes.length, customMetadata: o.customMetadata } : null;
  }
  async get(key, opts = {}) {
    const o = this.objects.get(key);
    if (!o) return null;
    const range = opts.range?.get?.('range');
    let offset = 0;
    let length = o.bytes.length;
    if (range) {
      const [a, b] = range.replace('bytes=', '').split('-').map(Number);
      offset = a;
      length = (Number.isFinite(b) ? b : o.bytes.length - 1) - a + 1;
    }
    return {
      body: o.bytes.slice(offset, offset + length),
      customMetadata: o.customMetadata,
      size: o.bytes.length,
      httpEtag: o.httpEtag,
      range: range ? { offset, length } : undefined,
    };
  }
  async delete(keys) {
    for (const k of [].concat(keys)) this.objects.delete(k);
  }
  async list({ prefix }) {
    return {
      objects: [...this.objects.entries()]
        .filter(([k]) => k.startsWith(prefix))
        .map(([key, o]) => ({ key, customMetadata: o.customMetadata })),
      truncated: false,
    };
  }
}

const env = () => ({ BOOTH: new FakeBucket() });

/// Bytes that pass the MP4 sniff ("ftyp" at 4..8), then [rest].
const mp4Body = (...rest) => new Uint8Array([0, 0, 0, 12, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0, ...rest]);

// ---------------------------------------------------------------- booth

const jpgBody = (...rest) => new Uint8Array([0xff, 0xd8, 0xff, 0xe0, ...rest]);
const boothEnv = () => ({ ...env(), BOOTH_KEY: 'booth-key', BOOTH_TTL_DAYS: '30' });
const BID = 'abcdefghjkmn';
const boothPut = (e, name, body, headers = {}, now = () => 1_000) =>
  worker.fetch(
    new Request(`https://lenslycam.com/lde/api/booth/${BID}/${name}`, { method: 'PUT', body, headers: { 'x-booth-key': 'booth-key', ...headers } }),
    e,
    {},
    now,
  );
const boothGet = (e, path, now = () => 2_000, headers = {}) =>
  worker.fetch(new Request(`https://lenslycam.com/lde/b/${BID}${path}`, { headers: { 'accept-language': 'vi-VN,vi;q=0.9', ...headers } }), e, {}, now);

test('booth: needs its own key, not the app key', async () => {
  const e = boothEnv();
  assert.equal((await boothPut(e, 'print.jpg', jpgBody(1), { 'x-booth-key': 'secret-key' })).status, 403);
  assert.equal((await boothPut({ ...env() }, 'print.jpg', jpgBody(1), { 'x-booth-key': '' })).status, 403);
  assert.equal((await boothPut(e, 'print.jpg', jpgBody(1))).status, 201);
});

test('booth: checks file types and names', async () => {
  const e = boothEnv();
  assert.equal((await boothPut(e, '1.jpg', mp4Body())).status, 415);
  assert.equal((await boothPut(e, '1.mp4', jpgBody())).status, 415);
  assert.equal((await boothPut(e, '1.mp4', mp4Body())).status, 201);
  assert.equal((await boothPut(e, '6.jpg', jpgBody())).status, 201);
  assert.equal((await boothPut(e, '7.jpg', jpgBody())).status, 404);
  assert.equal((await boothPut(e, 'print.mp4', mp4Body())).status, 404);
});

test('booth: page waits before any upload, then shows what arrived', async () => {
  const e = boothEnv();
  let r = await boothGet(e, '');
  assert.equal(r.status, 200);
  let html = await r.text();
  assert.match(html, /đang được tải lên/);
  assert.match(html, /status\.json/);
  await boothPut(e, 'print.jpg', jpgBody(9), { 'x-booth-title': encodeURIComponent('Tiệc <b>cuối năm</b>') });
  await boothPut(e, '1.jpg', jpgBody(1));
  await boothPut(e, '1.mp4', mp4Body(1));
  html = await (await boothGet(e, '')).text();
  assert.match(html, /Tiệc &lt;b&gt;cuối năm&lt;\/b&gt;/);
  assert.match(html, /\/lde\/b\/abcdefghjkmn\/print\.jpg\?dl=1/);
  assert.match(html, /<img src="\/lde\/b\/abcdefghjkmn\/1\.jpg"/);
  // No layout.json yet: the print is shown still, no composed video.
  assert.doesNotMatch(html, /id="compose"/);
  assert.match(html, /đang tải…/);
  assert.match(html, /status\.json/);
  // 30 minutes on, missing clips are given up on.
  html = await (await boothGet(e, '', () => 1_000 + 31 * 60 * 1000)).text();
  assert.doesNotMatch(html, /status\.json/);
  assert.doesNotMatch(html, /đang được tải lên/);
  assert.match(html, /không có/);
});

test('booth: files are served, downloadable, and expire after BOOTH_TTL_DAYS', async () => {
  const e = boothEnv();
  await boothPut(e, '2.mp4', mp4Body(1, 2, 3));
  let r = await boothGet(e, '/2.mp4?dl=1');
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('content-type'), 'video/mp4');
  assert.match(r.headers.get('content-disposition'), /attachment/);
  r = await boothGet(e, '/2.mp4', () => 2_000, { range: 'bytes=0-3' });
  assert.equal(r.status, 206);
  assert.equal((await boothGet(e, '/3.mp4')).status, 404);
  assert.equal((await boothGet(e, '/2.mp4', () => 1_000 + 30 * DAY)).status, 404);
  assert.equal((await boothGet(e, '', () => 1_000 + 30 * DAY)).status, 404);
});

test('booth: a retry keeps the first upload time', async () => {
  const e = boothEnv();
  await boothPut(e, 'print.jpg', jpgBody(1), {}, () => 1_000);
  await boothPut(e, 'print.jpg', jpgBody(2), {}, () => 5 * DAY);
  assert.equal(e.BOOTH.objects.get(`booth/${BID}/print.jpg`).customMetadata.uploaded, '1000');
});

test('booth: the daily sweep removes expired sessions', async () => {
  const e = boothEnv();
  await boothPut(e, 'print.jpg', jpgBody(1));
  assert.equal(await sweep(e, 1_000 + 29 * DAY), 0);
  assert.equal(await sweep(e, 1_000 + 30 * DAY), 1);
});

test('booth: layout.json puts each clip in its window of the print, with "Tải video ghép"', async () => {
  const e = boothEnv();
  const enc = (o) => new TextEncoder().encode(JSON.stringify(o));
  assert.equal((await boothPut(e, 'layout.json', enc({ aspect: 0.6757, rects: [[0.05, 0.03, 0.9, 0.4]] }))).status, 201);
  assert.equal((await boothPut(e, 'layout.json', enc({ aspect: 0.6757, rects: [[0.05, 0.03, 1.9, 0.4]] }))).status, 400);
  assert.equal((await boothPut(e, 'layout.json', new TextEncoder().encode('nope'))).status, 400);
  await boothPut(e, 'layout.json', enc({ aspect: 0.6757, rects: [[0.05, 0.03, 0.9, 0.4], [0.05, 0.5, 0.9, 0.4]] }));
  await boothPut(e, 'print.jpg', jpgBody(9));
  await boothPut(e, '2.mp4', mp4Body(2));
  const html = await (await boothGet(e, '')).text();
  // Only clip 2 arrived: one video, in window 2; window 1 says its video is coming, no compose yet.
  assert.match(html, /<div class="print" style="aspect-ratio:0.6757"><img src="\/lde\/b\/abcdefghjkmn\/print\.jpg"/);
  assert.match(html, /<video src="\/lde\/b\/abcdefghjkmn\/2\.mp4"[^>]*style="left:5\.000%;top:50\.000%;width:90\.000%;height:40\.000%"/);
  assert.doesNotMatch(html, /<video src="\/lde\/b\/abcdefghjkmn\/1\.mp4"/);
  assert.match(html, /<div class="vwait" style="left:5\.000%;top:3\.000%;width:90\.000%;height:40\.000%">/);
  assert.match(html, /Video Live đang được tải lên/);
  assert.match(html, /Video đang tải lên…/);
  assert.doesNotMatch(html, /id="compose"/);
  assert.match(html, /clip đang tải…/);
  // Two photos expected (from the layout): still waiting for the rest.
  assert.match(html, /status\.json/);
  assert.equal((await (await boothGet(e, '/status.json')).json()).n, 3);
  // Every file in: compose with both windows, no more waiting notes.
  for (const n of ['1.jpg', '2.jpg', '1.mp4']) await boothPut(e, n, n.endsWith('mp4') ? mp4Body(1) : jpgBody(1));
  const done = await (await boothGet(e, '')).text();
  assert.match(done, /id="compose"/);
  assert.match(done, /const R=\[\[0\.05,0\.03,0\.9,0\.4\],\[0\.05,0\.5,0\.9,0\.4\]\]/);
  assert.doesNotMatch(done, /class="vwait"|đang được tải lên|status\.json/);
  assert.equal((html.match(/class="tile"/g) || []).length, 2);
});

test('only /lde/ is answered here (the rest of lenslycam.com stays with Lensly)', async () => {
  const e = boothEnv();
  for (const p of ['/', '/v/abcdefghjkmn', '/b/abcdefghjkmn', '/api/booth/abcdefghjkmn/print.jpg']) {
    assert.equal((await worker.fetch(new Request(`https://lenslycam.com${p}`), e, {})).status, 404, p);
  }
});

test('the page loads fonts and files from /lde/', async () => {
  const e = boothEnv();
  await boothPut(e, 'print.jpg', jpgBody(1));
  const html = await (await boothGet(e, '')).text();
  assert.match(html, /url\(\/lde\/fonts\/PlayfairDisplay-Bold\.ttf\)/);
  assert.match(html, /url\(\/lde\/fonts\/BeVietnamPro-Regular\.ttf\)/);
  assert.doesNotMatch(html, /url\(\/fonts\//);
  assert.match(html, /src="\/lde\/b\/abcdefghjkmn\/print\.jpg"/);
});

test('the page speaks the phone language: ja, en, unknown → en, ?lang= wins', async () => {
  const e = boothEnv();
  await boothPut(e, 'print.jpg', jpgBody(1));
  const get = async (lang, q = '') => (await worker.fetch(new Request(`https://lenslycam.com/lde/b/${BID}${q}`, { headers: { 'accept-language': lang } }), e, {}, () => 2_000)).text();
  const ja = await get('ja-JP,ja;q=0.9');
  assert.match(ja, /<html lang="ja">/);
  assert.match(ja, /プリントをダウンロード/);
  assert.match(ja, /<b>日本語<\/b>/);
  const en = await get('en-US,en;q=0.9');
  assert.match(en, /Download the print/);
  assert.match(await get('fr-FR'), /Download the print/);
  const forced = await get('ja-JP', '?lang=vi');
  assert.match(forced, /Tải ảnh in/);
  assert.match(forced, /<a href="\?lang=ja">日本語<\/a>/);
  // Expired page too.
  const gone = await (await worker.fetch(new Request(`https://lenslycam.com/lde/b/${BID}`, { headers: { 'accept-language': 'ja' } }), e, {}, () => 1_000 + 31 * DAY)).text();
  assert.match(gone, /写真の公開期間が終了しました/);
});

test('the header shows the event text from layout.json; the title is gold with an italic tail', async () => {
  const e = boothEnv();
  const enc = (o) => new TextEncoder().encode(JSON.stringify(o));
  await boothPut(e, 'layout.json', enc({ aspect: 0.6757, rects: [[0.05, 0.03, 0.9, 0.4]], title: 'LPE Sum Up', subtitle: 'Tiệc tổng kết <cuối năm>', date: '23.12.2026' }));
  await boothPut(e, 'print.jpg', jpgBody(9));
  const html = await (await boothGet(e, '')).text();
  assert.match(html, /<div class="serif gold brandTitle">LPE <i>Sum Up<\/i><\/div>/);
  assert.match(html, /Tiệc tổng kết &lt;cuối năm&gt; 1970/);
  assert.match(html, /<div class="sub">23\.12\.2026<\/div>/);
  assert.match(html, /Ảnh của bạn/);
  assert.match(html, /LPE SUM UP · PHOTOBOOTH/);
});
