// LDE event photobooth: share pages for the iPad app (../photobooth), on its own.
// Served at lenslycam.com/lde/* by a Workers route (more specific than the
// lenslycam.com custom domain of Lensly's own Worker, so it wins), with its own
// R2 bucket (lde-booth) and secret (BOOTH_KEY). Nothing here is shared with the
// live Lensly app: the helpers and page style below are copies from Lensly's
// server/share-worker, not imports.
//
//   PUT  /lde/api/booth/<id>/<f>  (X-Booth-Key) one file of a session, f = print.jpg |
//                                 layout.json | 1..6.jpg | 1..6.mp4; the iPad picks <id> so
//                                 the QR is printed before anything is uploaded
//   GET  /lde/b/<id>              the guest page: the print with each Live clip playing in its
//                                 window (layout.json), "Tải video ghép" (composed in the
//                                 browser), each photo / clip to download; while clips are
//                                 still coming it says so and reloads when a file arrives
//   GET  /lde/b/<id>/<f>          one file (Range; ?dl=1 → attachment)
//   GET  /lde/b/<id>/status.json  { n: files uploaded } (the page polls it)
//   GET  /lde/fonts/*             the page fonts (static assets)
//
// Files expire BOOTH_TTL_DAYS (30) after upload: pages answer 404, a daily cron
// deletes them, and the bucket lifecycle rule is a second net.

export const BASE = '/lde';

const ID_ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789'; // no 0/o, 1/l/i
const ID_LENGTH = 12;
const DAY_MS = 24 * 60 * 60 * 1000;

/// Constant-time string compare (the app key must not leak by timing).
export function sameKey(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length || a.length === 0) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// 'image/jpeg' / 'image/png' from the first bytes, or null.
export function imageType(bytes) {
  if (bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return 'image/png';
  return null;
}

/// The cell windows sent with a frame: n rects of 4 fractions in 0..1, or null.
export function parseRects(text, n) {
  let r;
  try {
    r = JSON.parse(text);
  } catch {
    return null;
  }
  const ok = (v) => typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= 1;
  if (!Array.isArray(r) || r.length !== n || !r.every((q) => Array.isArray(q) && q.length === 4 && q.every(ok))) return null;
  return r.map((q) => q.map((v) => Math.round(v * 10000) / 10000));
}

/// An MP4 starts with a box whose type (bytes 4..8) is "ftyp".
export function looksLikeMp4(bytes) {
  return bytes.length >= 12 && bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}

/// The album title shown on its page: plain text, one line, ≤ 60 characters.
export function cleanTitle(raw) {
  const t = String(raw ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  return [...t].slice(0, 60).join('');
}

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

/// JSON for an inline <script>: no "</script>", "<!--" or line separators
/// can come out of it.
function scriptJson(value) {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

// Fills `{name}` in an injected string (same as fill above).
const SCRIPT_FILL = `const F=(s,o)=>Object.keys(o).reduce((a,k)=>a.split('{'+k+'}').join(String(o[k])),s);`;

// Same flea-market palette as the app (lib/core/tokens.dart): a gingham
// cloth like the gallery, the print taped onto it, handwritten title.
// LPE Sum Up design ("Web khách"): night background with a navy glow, champagne gold, glass,
// Playfair Display + Be Vietnam Pro served from /lde/fonts (no third party sees the guests).
const STYLE = `
:root{--night:#0B0B12;--gold:#D4AF6A;--gold-l:#F5E1A4;--ivory:#F8F3E8;--rose:#E9C7C0;--muted:rgba(248,243,232,.6)}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%}
body{position:relative;background:radial-gradient(140% 40% at 50% 0%,#1d2448 0%,#0B0B12 62%) #0B0B12;color:var(--ivory);
font:15px/1.5 "Be Vietnam Pro","Hiragino Sans","Noto Sans JP",system-ui,sans-serif;overflow-x:hidden}
main{position:relative;max-width:460px;margin:0 auto;padding:40px 20px 120px}
.serif{font-family:"Playfair Display","Hiragino Mincho ProN","Noto Serif JP",Georgia,serif}
.eyebrow{font-weight:600;text-transform:uppercase;letter-spacing:.3em;font-size:11px;color:rgba(248,243,232,.75)}
.gold{background:linear-gradient(100deg,#9C7A3F 0%,#D4AF6A 22%,#F5E1A4 45%,#FFF6DA 50%,#F5E1A4 55%,#D4AF6A 78%,#9C7A3F 100%);background-size:220% 100%;
background-position:100% 0;-webkit-background-clip:text;background-clip:text;color:transparent;-webkit-text-fill-color:transparent;animation:sweep 6s cubic-bezier(.45,0,.55,1) infinite}
@keyframes sweep{0%,100%{background-position:100% 0}50%{background-position:0% 0}}
header{text-align:center}
.brandTitle{margin-top:8px;font-size:40px;font-weight:700;line-height:1.1}
.brandTitle i{font-weight:400}
.deco{display:flex;align-items:center;justify-content:center;gap:12px;margin-top:10px}
.deco span{display:block}.deco .l{width:52px;height:1px;background:linear-gradient(90deg,rgba(212,175,106,0),#D4AF6A)}
.deco .r{width:52px;height:1px;background:linear-gradient(90deg,#D4AF6A,rgba(212,175,106,0))}
.deco .o{width:7px;height:7px;transform:rotate(45deg);border:1px solid #D4AF6A}.deco .f{width:6px;height:6px;transform:rotate(45deg);background:#D4AF6A}
.glass{background:linear-gradient(180deg,rgba(30,28,42,.62),rgba(14,13,22,.74));-webkit-backdrop-filter:blur(18px) saturate(1.2);backdrop-filter:blur(18px) saturate(1.2);
border:1px solid rgba(212,175,106,.28)}
.notice{margin:22px 0 0;padding:14px 16px;border-radius:18px;display:flex;gap:14px;align-items:flex-start;font-size:14px;line-height:1.5}
.spinner{display:block;flex:none;border-radius:50%;border:3px solid rgba(212,175,106,.2);border-top-color:#F5E1A4;border-right-color:#D4AF6A;animation:spin 1s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
h1{margin:26px 0 0;text-align:center;font-size:28px;font-weight:600}
.sub{margin-top:4px;text-align:center;font-size:13px;color:var(--muted)}
.stage{position:relative;margin:22px auto 0}
.print{position:relative;width:100%;border-radius:6px;overflow:hidden;box-shadow:0 24px 50px rgba(0,0,0,.6),0 0 0 1px rgba(212,175,106,.35)}
.print img{display:block;width:100%;height:100%}
.print video{position:absolute;object-fit:cover;background:transparent}
.print .vwait{position:absolute;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;
background:rgba(11,11,18,.55);color:var(--ivory);font-size:12px;letter-spacing:.04em}
.pwait{margin-top:22px;padding:60px 20px;border-radius:18px;text-align:center;color:var(--muted)}
.actions{margin:26px 0 0;display:flex;flex-direction:column;gap:12px}
.btn-gold,.btn-line{position:relative;overflow:hidden;display:flex;align-items:center;justify-content:center;gap:10px;width:100%;height:56px;border-radius:999px;
font:600 17px "Be Vietnam Pro","Hiragino Sans",sans-serif;text-decoration:none;cursor:pointer;-webkit-tap-highlight-color:transparent}
.btn-gold{border:0;background:linear-gradient(180deg,#F5E1A4 0%,#E6C886 40%,#D4AF6A 70%,#B8914F 100%);color:#1A1408;
box-shadow:inset 0 0 0 1px rgba(255,244,214,.6),inset 0 -3px 0 rgba(120,85,30,.35),0 10px 30px rgba(212,175,106,.28),0 2px 6px rgba(0,0,0,.5);
transition:transform 140ms cubic-bezier(.2,.8,.2,1),box-shadow 140ms}
.btn-gold::after{content:"";position:absolute;top:0;bottom:0;left:-60%;width:45%;background:linear-gradient(100deg,rgba(255,255,255,0),rgba(255,255,255,.8),rgba(255,255,255,0));
transform:skewX(-20deg);animation:shimmer 3s cubic-bezier(.4,0,.2,1) infinite;pointer-events:none}
@keyframes shimmer{0%{left:-60%}28%{left:130%}100%{left:130%}}
.btn-gold:active{transform:translateY(3px) scale(.97);box-shadow:inset 0 0 0 1px rgba(255,244,214,.7),0 0 44px rgba(245,225,164,.75)}
.btn-gold.off{background:linear-gradient(180deg,#4a4434,#3a3528);color:rgba(248,243,232,.45);box-shadow:inset 0 0 0 1px rgba(212,175,106,.25);pointer-events:none}
.btn-gold.off::after{display:none}
.btn-line{border:1.5px solid rgba(212,175,106,.7);background:rgba(11,11,18,.35);color:var(--ivory);font-weight:500}
.btn-line:active{background:rgba(212,175,106,.16)}
.btn-gold svg,.btn-line svg{width:18px;height:18px;flex:none}
section{margin:40px 0 0}
.sechead{display:flex;align-items:baseline;justify-content:space-between}
h2{margin:0;font-size:22px;font-weight:600}
.count{font-size:13px;color:var(--muted)}
.grid{margin-top:14px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px 12px}
.tile{display:flex;align-items:center;justify-content:center;width:100%;aspect-ratio:16/10;border-radius:12px;overflow:hidden;background:#17141c;
box-shadow:0 0 0 1px rgba(212,175,106,.3),0 8px 20px rgba(0,0,0,.4);color:var(--muted);font-size:12px}
.tile img,.tile video{display:block;width:100%;height:100%;object-fit:cover}
.links{margin-top:8px;display:flex;align-items:center;gap:8px;font-size:14px}
.links .n{color:var(--muted)}.links .dot{color:rgba(248,243,232,.4)}
.lnk{font-weight:500;color:var(--gold-l);text-decoration:underline;text-underline-offset:3px;text-decoration-color:rgba(245,225,164,.45)}
.lnk.muted{color:var(--muted);text-decoration:none}
.note{margin:30px 0 0;text-align:center;font-size:13px;color:var(--rose)}
p{color:var(--muted);font-size:12px;text-align:center;margin:10px 0}
.langs a{color:var(--gold-l)}.langs b{color:var(--ivory)}
footer{margin-top:40px;text-align:center}
footer .deco .l,footer .deco .r{width:40px}
footer .tag{margin-top:12px;font-size:12px;letter-spacing:.12em;color:rgba(248,243,232,.5)}
.gone{margin-top:18vh}
.corner{position:absolute;width:46px;height:46px;opacity:.8;pointer-events:none}
.c1{left:12px;top:12px}.c2{right:12px;top:12px;transform:scaleX(-1)}
.dust{position:absolute;border-radius:50%;background:radial-gradient(circle,#FFF6DA 0%,#F5E1A4 40%,rgba(212,175,106,0) 72%);
box-shadow:0 0 6px 1px rgba(245,225,164,.55);pointer-events:none;animation:drift ease-in-out infinite alternate,twinkle ease-in-out infinite}
@keyframes drift{to{transform:translateY(-70px)}}
@keyframes twinkle{0%,100%{opacity:.15}50%{opacity:.95}}
details.bm{display:none}
@media (prefers-reduced-motion:reduce){.gold,.btn-gold::after,.dust{animation:none}}`;

const FONTS = [
  ['Playfair Display', 400, 'normal', 'PlayfairDisplay-Regular'],
  ['Playfair Display', 600, 'normal', 'PlayfairDisplay-SemiBold'],
  ['Playfair Display', 700, 'normal', 'PlayfairDisplay-Bold'],
  ['Playfair Display', 400, 'italic', 'PlayfairDisplay-Italic'],
  ['Be Vietnam Pro', 400, 'normal', 'BeVietnamPro-Regular'],
  ['Be Vietnam Pro', 500, 'normal', 'BeVietnamPro-Medium'],
  ['Be Vietnam Pro', 600, 'normal', 'BeVietnamPro-SemiBold'],
]
  .map(([f, w, st, file]) => `@font-face{font-family:"${f}";font-weight:${w};font-style:${st};src:url(${BASE}/fonts/${file}.ttf) format("truetype");font-display:swap}`)
  .join('');

/// The design's art-deco corner (120-unit SVG at 46 px), top left and mirrored top right.
const CORNER =
  '<path d="M1 119V1h118"/><path d="M10 86V10h76"/><path d="M10 46a36 36 0 0 1 36-36"/><path d="M10 31a21 21 0 0 1 21-21"/>' +
  '<path d="M10 10l20 20"/><path d="M36 28l6 6-6 6-6-6z" fill="#D4AF6A"/><path d="M1 64h6M64 1v6"/>';
const corners = ['c1', 'c2']
  .map((c) => `<svg class="corner ${c}" aria-hidden="true" viewBox="0 0 120 120" fill="none" stroke="#D4AF6A" stroke-width="2.4">${CORNER}</svg>`)
  .join('');

/// LOW glitter (design: the guest page gets the lightest level): 24 drifting, twinkling dots.
const DUST = Array.from({ length: 24 }, (_, i) => {
  const r = (k) => ((Math.sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1 + 1) % 1;
  const size = (1.8 + r(1) * (r(2) < 0.18 ? 5.7 : 2.2)).toFixed(1);
  return `<span class="dust" style="left:${(r(3) * 100).toFixed(1)}%;top:${(r(4) * 100).toFixed(1)}%;width:${size}px;height:${size}px;` +
    `animation-duration:${(8 + r(5) * 8).toFixed(1)}s,${(1.8 + r(6) * 2.2).toFixed(1)}s;animation-delay:-${(r(7) * 10).toFixed(1)}s,-${(r(8) * 4).toFixed(1)}s"></span>`;
}).join('');

const SECURITY_HEADERS = {
  'referrer-policy': 'no-referrer',
  'x-content-type-options': 'nosniff',
  'content-security-policy':
    "default-src 'none'; img-src 'self' data: blob:; media-src 'self'; font-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; " +
    "script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
};

function page(lang, title, body) {
  return new Response(
    `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">` +
      `<meta name="robots" content="noindex"><meta name="theme-color" content="#0B0B12"><title>${escapeHtml(title)}</title>` +
      `<style>${FONTS}${STYLE}</style></head>` +
      `<body><div aria-hidden="true" style="position:absolute;inset:0;overflow:hidden;pointer-events:none">${DUST}</div>${corners}` +
      `<main>${body}<footer>${DECO}<div class="tag">LPE SUM UP · PHOTOBOOTH</div></footer></main></body></html>`,
    {
      headers: {
        'content-type': 'text/html; charset=utf-8',
        // The language comes from Accept-Language: never cached, and Vary keeps any cache honest.
        'cache-control': 'no-store',
        vary: 'Accept-Language',
        ...SECURITY_HEADERS,
      },
    },
  );
}

const DECO = '<div class="deco" aria-hidden="true"><span class="l"></span><span class="o"></span><span class="f"></span><span class="o"></span><span class="r"></span></div>';

/// "LPE *Sum Up*": the first word bold, the rest italic, in moving gold.
function brandTitle(title) {
  const [head, ...tail] = String(title).trim().split(/\s+/);
  return `<div class="serif gold brandTitle">${escapeHtml(head ?? '')}${tail.length ? ` <i>${escapeHtml(tail.join(' '))}</i>` : ''}</div>`;
}

const DL_ICON =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
  '<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/></svg>';

/// Records the print + all cells into one clip. mp4 where the browser can
/// (Safari, Chrome 126+), else webm. Mobile: share sheet ("Lưu video");
/// desktop: a normal download.
/// Saves a file the page just made. Phones get the share sheet ("Lưu video",
/// "Lưu vào Tệp"), but browsers only open it right after a tap: when making
/// the file took longer than that (composing a video takes as long as the
/// clip), share() is refused with NotAllowedError and the file is downloaded
/// straight away instead, so one tap is always enough (owner 2026-10-09: it
/// used to need a second tap). The next tap on the button opens the share
/// sheet with the same file. Defines mobile() and saveFile(file) → 'shared' |
/// 'downloaded' | 'cancelled'.
export const SAVE_FILE =
  `const mobile=()=>/Mobi|Android|iPhone|iPad/.test(navigator.userAgent);` +
  `const download=(file)=>{const a=document.createElement('a');a.href=URL.createObjectURL(file);a.download=file.name;` +
  `document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},60000)};` +
  `const saveFile=async(file)=>{if(mobile()&&navigator.canShare&&navigator.canShare({files:[file]})){` +
  `try{await navigator.share({files:[file]});return 'shared'}` +
  `catch(e){if(!e||e.name!=='NotAllowedError')return 'cancelled'}}` +
  `download(file);return 'downloaded'};`;

function composeScript(id, rects, lang = 'vi') {
  return `<script>(()=>{` +
    `const R=${JSON.stringify(rects)},ID=${JSON.stringify(id)};` + SAVE_FILE +
    `const S=${scriptJson(Object.fromEntries(['composing', 'composedSaved', 'composeAgain', 'composeFailed'].map((k) => [k, W[lang][k]])))};` + SCRIPT_FILL +
    `const btn=document.getElementById('compose'),label=btn.querySelector('span'),more=document.querySelector('details.cells');` +
    // H.264 mp4 first (iPhone Photos, Android gallery), then any mp4 (has a
    // proper duration), webm last (MediaRecorder webm has no duration).
    `const types=['video/mp4;codecs=avc1.42E01E','video/mp4;codecs=avc1','video/mp4','video/webm;codecs=vp9','video/webm;codecs=vp8','video/webm'];` +
    `const type=window.MediaRecorder&&HTMLCanvasElement.prototype.captureStream?types.find(t=>MediaRecorder.isTypeSupported(t)):null;` +
    `if(!type){btn.parentNode.remove();more.hidden=false;more.open=true;return}` +
    `more.hidden=false;let busy=false,blob=null;` +
    `const wait=(el,ev)=>new Promise(r=>el.addEventListener(ev,r,{once:true}));` +
    `async function make(){` +
      `const img=document.querySelector('.print img'),over=document.querySelector('.print img.over'),vids=[...document.querySelectorAll('.print video')];` +
      `if(!img.complete)await wait(img,'load');if(over&&!over.complete)await wait(over,'load');` +
      // Long side ≤ 1920, short side ≤ 1080, even sizes (H.264 encoders).
      `let w=img.naturalWidth,h=img.naturalHeight;const k=Math.min(1,1920/Math.max(w,h),1080/Math.min(w,h));` +
      `w=Math.round(w*k/2)*2;h=Math.round(h*k/2)*2;` +
      `const c=document.createElement('canvas');c.width=w;c.height=h;const g=c.getContext('2d');` +
      `window.__fctComposing=true;` +
      `for(const v of vids){v.pause();v.loop=false;if(v.readyState<1)await wait(v,'loadedmetadata');v.currentTime=0}` +
      `await Promise.all(vids.map(v=>v.seeking?wait(v,'seeked'):0));` +
      `const dur=Math.max(...vids.map(v=>v.duration||0))||5;` +
      `const draw=()=>{g.drawImage(img,0,0,w,h);vids.forEach((v,i)=>{const[x,y,rw,rh]=R[i],dx=x*w,dy=y*h,dw=rw*w,dh=rh*h;` +
        `const vw=v.videoWidth,vh=v.videoHeight;if(!vw||!vh)return;const s=Math.max(dw/vw,dh/vh),sw=dw/s,sh=dh/s;` +
        `g.drawImage(v,(vw-sw)/2,(vh-sh)/2,sw,sh,dx,dy,dw,dh)});if(over)g.drawImage(over,0,0,w,h)};` +
      `draw();const rec=new MediaRecorder(c.captureStream(30),{mimeType:type,videoBitsPerSecond:6e6});const parts=[];` +
      `rec.ondataavailable=e=>e.data.size&&parts.push(e.data);const stopped=wait(rec,'stop');` +
      `rec.start(250);const t0=performance.now();await Promise.all(vids.map(v=>v.play().catch(()=>{})));` +
      `await new Promise(r=>{const tick=()=>{draw();const left=dur-(performance.now()-t0)/1000;` +
        `label.textContent=F(S.composing,{s:Math.max(0,Math.ceil(left))});` +
        `if(left<=0||vids.every(v=>v.ended))r();else requestAnimationFrame(tick)};tick()});` +
      `draw();rec.stop();await stopped;window.__fctComposing=false;vids.forEach(v=>{v.loop=false;v.currentTime=0;v.play().catch(()=>{})});` +
      `return new Blob(parts,{type:type.split(';')[0]})}` +
    `btn.addEventListener('click',async e=>{e.preventDefault();if(busy)return;busy=true;btn.style.opacity=.8;` +
      `try{blob=blob||await make();const ext=blob.type.includes('mp4')?'mp4':'webm',name='photobooth-'+ID+'.'+ext;` +
      `const file=new File([blob],name,{type:blob.type});const how=await saveFile(file);` +
      `label.textContent=how==='downloaded'&&mobile()?S.composedSaved:S.composeAgain}` +
      `catch(err){label.textContent=S.composeFailed;more.open=true}` +
      `finally{busy=false;btn.style.opacity=1;window.__fctComposing=false}})` +
    `})()</script>`;
}

// Cells start together and restart together once the longest has ended.
const SYNC_SCRIPT =
  `<script>(()=>{const v=[...document.querySelectorAll('.stage video')];let done=0;` +
  `const all=()=>v.forEach(x=>{x.currentTime=0;x.play().catch(()=>{})});` +
  `v.forEach(x=>x.addEventListener('ended',()=>{if(window.__fctComposing)return;if(++done>=v.length){done=0;all()}}));` +
  `document.addEventListener('click',all,{once:true})})()</script>`;

export function isValidId(id) {
  return typeof id === 'string' && id.length === ID_LENGTH && [...id].every((c) => ID_ALPHABET.includes(c));
}

export function expiresAt(uploadedMs, ttlDays) {
  return uploadedMs + ttlDays * DAY_MS;
}

export function isExpired(uploadedMs, nowMs, ttlDays) {
  return !Number.isFinite(uploadedMs) || nowMs >= expiresAt(uploadedMs, ttlDays);
}

// ---------------------------------------------------------------- languages
// The guest page speaks the phone's language: ?lang=vi|en|ja, else the first of vi / ja / en in
// Accept-Language, else English.
export const LANGS = ['vi', 'en', 'ja'];
const LANG_NAMES = { vi: 'Tiếng Việt', en: 'English', ja: '日本語' };

export const W = {
  vi: {
    yourPhotos: 'Ảnh của bạn',
    eachPhoto: 'Từng ảnh',
    counts: '{p} ảnh · {c} clip',
    composing: 'Đang ghép video… {s}s',
    composedSaved: 'Đã tải · Lưu vào Ảnh',
    composeAgain: 'Tải lại video',
    composeFailed: 'Chưa ghép được, thử tải từng ô',
    gone: 'Ảnh đã hết hạn',
    goneText: 'Ảnh và clip chỉ được giữ {n} ngày.',
    uploading: 'Ảnh đang được tải lên…<br>Trang sẽ tự cập nhật.',
    videoLoading: 'Đang tải video…',
    videosComing: 'Video Live đang được tải lên, vui lòng đợi ít phút. Trang sẽ tự cập nhật.',
    downloadComposed: 'Tải video ghép',
    videosUploading: 'Video đang tải lên…',
    downloadPrint: 'Tải ảnh in',
    printAlt: 'Ảnh in',
    photo: 'Ảnh',
    clip: 'Clip',
    loading: 'đang tải…',
    none: 'không có',
    clipLoading: 'clip đang tải…',
    saveBefore: 'Lưu về máy trước ngày {date}',
    help: '"Tải video ghép": cả tấm ảnh với các clip chạy cùng lúc, thành một video. Chạm "Ảnh" hoặc "Clip" để tải từng cái. Trên iPhone: mở bằng Safari.',
  },
  en: {
    yourPhotos: 'Your photos',
    eachPhoto: 'Each photo',
    counts: '{p} photos · {c} clips',
    composing: 'Making your video… {s}s',
    composedSaved: 'Downloaded · save to Photos',
    composeAgain: 'Download again',
    composeFailed: 'Could not make it, download each clip instead',
    gone: 'These photos have expired',
    goneText: 'Photos and clips are kept for {n} days.',
    uploading: 'Your photos are uploading…<br>This page updates by itself.',
    videoLoading: 'Video coming…',
    videosComing: 'Live videos are uploading, please wait a few minutes. This page updates by itself.',
    downloadComposed: 'Download the video',
    videosUploading: 'Videos uploading…',
    downloadPrint: 'Download the print',
    printAlt: 'The print',
    photo: 'Photo',
    clip: 'Clip',
    loading: 'loading…',
    none: 'none',
    clipLoading: 'clip coming…',
    saveBefore: 'Save them before {date}',
    help: '"Download the video": the whole print with every clip playing, as one video. Tap "Photo" or "Clip" to download one by one. On iPhone, open this page in Safari.',
  },
  ja: {
    yourPhotos: 'あなたの写真',
    eachPhoto: '1枚ずつ',
    counts: '写真{p}枚 · 動画{c}本',
    composing: '動画を作成中… {s}秒',
    composedSaved: 'ダウンロード完了 · 写真に保存',
    composeAgain: 'もう一度ダウンロード',
    composeFailed: '作成できませんでした。1つずつ保存してね',
    gone: '写真の公開期間が終了しました',
    goneText: '写真と動画の保存期間は{n}日間です。',
    uploading: '写真をアップロード中…<br>このページは自動で更新されます。',
    videoLoading: '動画を読み込み中…',
    videosComing: 'Live動画をアップロード中です。数分お待ちください。ページは自動で更新されます。',
    downloadComposed: '動画をダウンロード',
    videosUploading: '動画をアップロード中…',
    downloadPrint: 'プリントをダウンロード',
    printAlt: 'プリント',
    photo: '写真',
    clip: '動画',
    loading: '読み込み中…',
    none: 'なし',
    clipLoading: '動画を読み込み中…',
    saveBefore: '{date}までに保存してね',
    help: '「動画をダウンロード」：プリント全体と各動画をまとめた1本の動画。「写真」「動画」で1つずつ保存できます。iPhoneはSafariで開いてね。',
  },
};

/// The guest's language for [request].
export function pickLang(request) {
  const q = new URL(request.url).searchParams.get('lang');
  if (LANGS.includes(q)) return q;
  for (const part of (request.headers.get('accept-language') ?? '').toLowerCase().split(',')) {
    const code = part.trim().slice(0, 2);
    if (LANGS.includes(code)) return code;
  }
  return 'en';
}

const w = (lang, key, vars = {}) => Object.keys(vars).reduce((a, k) => a.split(`{${k}}`).join(String(vars[k])), W[lang][key]);

/// The expiry date in Vietnam time (UTC+7), written the way [lang] does.
function dateFor(lang, ms) {
  const d = new Date(ms + 7 * 60 * 60 * 1000);
  const dd = String(d.getUTCDate()).padStart(2, '0'), mm = String(d.getUTCMonth() + 1).padStart(2, '0'), y = d.getUTCFullYear();
  if (lang === 'ja') return `${y}年${d.getUTCMonth() + 1}月${d.getUTCDate()}日`;
  if (lang === 'en') return `${d.getUTCDate()} ${'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split(' ')[d.getUTCMonth()]} ${y}`;
  return `${dd}/${mm}/${y}`;
}

/// Tiếng Việt · English · 日本語 at the foot of the page.
const langLinks = (lang) =>
  `<p class="langs">${LANGS.map((l) => (l === lang ? `<b>${LANG_NAMES[l]}</b>` : `<a href="?lang=${l}">${LANG_NAMES[l]}</a>`)).join(' · ')}</p>`;

// ---------------------------------------------------------------- booth
// The iPad makes the id itself and prints its QR before any upload, then PUTs
// the files one by one (print first, then photos, then clips) and retries
// until each one is in. Stored as booth/<id>/<file> in the BOOTH bucket.
// BOOTH_KEY lives only on the iPad, so no per-IP limit.
/// Files of a session with [n] photos (layout.json: the photo windows on the print, so the
/// clips can play in them).
export const boothFilesFor = (n) => ['print.jpg', 'layout.json', ...Array.from({ length: n }, (_, i) => [`${i + 1}.jpg`, `${i + 1}.mp4`]).flat()];
const BOOTH_MAX_PHOTOS = 6;
const boothKey = (id, name) => `booth/${id}/${name}`;
const boothTtl = (env) => Number(env.BOOTH_TTL_DAYS ?? 30);
/// A clip that failed on the iPad never comes: the page stops waiting this long after the first file.
const BOOTH_WAIT_MS = 30 * 60 * 1000;

async function boothPut(request, env, id, name, now) {
  if (!env.BOOTH_KEY || !sameKey(request.headers.get('x-booth-key') ?? '', env.BOOTH_KEY)) return json({ error: 'forbidden' }, 403);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (!bytes.length) return json({ error: 'empty' }, 400);
  if (bytes.length > Number(env.BOOTH_MAX_BYTES ?? 20971520)) return json({ error: 'too large' }, 413);
  const video = name.endsWith('.mp4');
  const layout = name === 'layout.json';
  if (layout) {
    if (!parseBoothLayout(new TextDecoder().decode(bytes))) return json({ error: 'bad layout' }, 400);
  } else if (video ? !looksLikeMp4(bytes) : imageType(bytes) !== 'image/jpeg') {
    return json({ error: 'bad type' }, 415);
  }
  // A retry overwrites the file but keeps the first upload time, so the link's days never restart.
  const old = await env.BOOTH.head(boothKey(id, name));
  const meta = { uploaded: old?.customMetadata?.uploaded ?? String(now()) };
  if (name === 'print.jpg') {
    let title = '';
    try {
      title = cleanTitle(decodeURIComponent(request.headers.get('x-booth-title') ?? ''));
    } catch {}
    if (title) meta.title = title;
  }
  await env.BOOTH.put(boothKey(id, name), bytes, {
    httpMetadata: { contentType: layout ? 'application/json' : video ? 'video/mp4' : 'image/jpeg' },
    customMetadata: meta,
  });
  return json({ ok: true }, 201);
}

/// layout.json → { aspect, rects } (rects: 1..6 windows as fractions of the print), or null.
export function parseBoothLayout(text) {
  let j;
  try {
    j = JSON.parse(text);
  } catch {
    return null;
  }
  const n = Array.isArray(j?.rects) ? j.rects.length : 0;
  if (n < 1 || n > BOOTH_MAX_PHOTOS) return null;
  const rects = parseRects(JSON.stringify(j.rects), n);
  const aspect = Number(j.aspect);
  if (!rects || !Number.isFinite(aspect) || aspect < 0.2 || aspect > 5) return null;
  // The event text for the page header (plain, one line, ≤ 60 characters each).
  return { aspect, rects, title: cleanTitle(j.title), subtitle: cleanTitle(j.subtitle), date: cleanTitle(j.date) };
}

/// The session's files: name → { uploaded, title }.
async function boothFiles(env, id) {
  const files = {};
  let cursor;
  do {
    const list = await env.BOOTH.list({ prefix: `booth/${id}/`, cursor, include: ['customMetadata'] });
    for (const o of list.objects) {
      files[o.key.slice(`booth/${id}/`.length)] = { uploaded: Number(o.customMetadata?.uploaded), title: o.customMetadata?.title };
    }
    cursor = list.truncated ? list.cursor : undefined;
  } while (cursor);
  return files;
}


const boothGone = (env, lang) => {
  const r = page(
    lang,
    w(lang, 'gone'),
    `<div class="gone"><header><div class="eyebrow">Photobooth</div>${DECO}</header>` +
      `<h1 class="serif">${w(lang, 'gone')}</h1><p>${w(lang, 'goneText', { n: boothTtl(env) })}</p></div>` +
      langLinks(lang),
  );
  return new Response(r.body, { status: 404, headers: r.headers });
};

async function boothView(env, id, now, ctx, lang = 'vi') {
  const files = await boothFiles(env, id);
  const times = Object.values(files).map((f) => f.uploaded).filter(Number.isFinite);
  const first = times.length ? Math.min(...times) : NaN;
  if (times.length && isExpired(first, now(), boothTtl(env))) {
    ctx?.waitUntil?.(env.BOOTH.delete(Object.keys(files).map((n) => boothKey(id, n))));
    return boothGone(env, lang);
  }
  const has = (n) => n in files;
  let layout = null;
  if (has('layout.json')) {
    const o = await env.BOOTH.get(boothKey(id, 'layout.json'));
    layout = o ? parseBoothLayout(new TextDecoder().decode(await new Response(o.body).arrayBuffer())) : null;
  }
  const count = layout?.rects.length ?? 4;
  // Nothing yet (the QR is printed before the upload starts) or still arriving: keep checking.
  const waiting = !times.length || (boothFilesFor(count).some((n) => !has(n)) && now() - first < BOOTH_WAIT_MS);
  const title = layout?.title || files['print.jpg']?.title || 'Photobooth';
  const src = (n) => `${BASE}/b/${id}/${n}`;
  const t = (key, vars) => w(lang, key, vars);
  const nums = Array.from({ length: count }, (_, i) => i + 1);
  // Clips come last (exported on the iPad after the photos): say so instead of a still that looks final.
  const clipsComing = waiting && nums.some((i) => !has(`${i}.mp4`));
  const spin = (px) => `<span class="spinner" aria-hidden="true" style="width:${px}px;height:${px}px${px < 20 ? ';border-width:2px' : ''}"></span>`;

  const header =
    `<header><div class="eyebrow">${escapeHtml([layout?.subtitle, new Date(now()).getUTCFullYear()].filter(Boolean).join(' '))}</div>` +
    brandTitle(title) + DECO + `</header>`;
  const notice = waiting && (clipsComing || !has('print.jpg'))
    ? `<div class="glass notice" role="status">${spin(22)}<span>${has('print.jpg') ? t('videosComing') : t('uploading')}</span></div>`
    : '';

  let print;
  if (!has('print.jpg')) {
    print = `<div class="glass pwait">${t('uploading')}</div>`;
  } else {
    // Like Lensly's strips: each Live clip plays in its photo window of the print.
    const live = layout ? nums.filter((i) => has(`${i}.mp4`)) : [];
    const pct = (v) => `${(v * 100).toFixed(3)}%`;
    const box = ([x, y, w, h]) => `left:${pct(x)};top:${pct(y)};width:${pct(w)};height:${pct(h)}`;
    const videos = live
      .map((i) => `<video src="${src(`${i}.mp4`)}" muted autoplay playsinline preload="auto" style="${box(layout.rects[i - 1])}"></video>`)
      .join('');
    // Windows whose clip has not arrived: the still stays, with "Đang tải video…" over it.
    const pending = clipsComing && layout
      ? nums.filter((i) => !has(`${i}.mp4`)).map((i) => `<div class="vwait" style="${box(layout.rects[i - 1])}">${spin(18)}${t('videoLoading')}</div>`).join('')
      : '';
    const aspect = layout?.aspect ?? 1200 / 1776;
    const compose = live.length && !clipsComing;
    print =
      `<div class="stage" style="width:min(100%, calc(62vh * ${aspect}))">` +
      `<div class="print" style="aspect-ratio:${aspect}"><img src="${src('print.jpg')}" alt="${t('printAlt')}">${videos}${pending}</div></div>` +
      `<div class="actions">` +
      (compose
        ? `<a class="btn-gold" id="compose" href="#" role="button">${DL_ICON}<span>${t('downloadComposed')}</span></a>`
        : clipsComing
          ? `<a class="btn-gold off" aria-disabled="true">${spin(18)}<span>${t('videosUploading')}</span></a>`
          : '') +
      `<a class="btn-line" href="${src('print.jpg')}?dl=1" download>${DL_ICON}${t('downloadPrint')}</a></div>` +
      (live.length ? SYNC_SCRIPT : '') +
      (compose ? `<details class="cells bm" hidden></details>` + composeScript(id, live.map((i) => layout.rects[i - 1]), lang) : '');
  }

  const clips = nums.filter((i) => has(`${i}.mp4`)).length;
  const cells = nums
    .map((i) => {
      const jpg = `${i}.jpg`, mp4 = `${i}.mp4`;
      const media = has(jpg)
        ? `<img src="${src(jpg)}" alt="${t('photo')} ${i}" loading="lazy">`
        : waiting ? `${spin(20)}` : t('none');
      const photo = has(jpg) ? `<a class="lnk" href="${src(jpg)}?dl=1" download>${t('photo')}</a>` : '';
      const clip = has(mp4)
        ? `<a class="lnk" href="${src(mp4)}?dl=1" download>${t('clip')}</a>`
        : waiting ? `<span class="lnk muted">${t('clipLoading')}</span>` : '';
      return `<div><div class="tile">${media}</div><div class="links"><span class="n">#${i}</span>` +
        [photo, clip].filter(Boolean).join('<span class="dot">·</span>') + `</div></div>`;
    })
    .join('');

  return page(
    lang,
    title,
    header +
      notice +
      `<h1 class="serif">${t('yourPhotos')}</h1>` +
      (layout?.date ? `<div class="sub">${escapeHtml(layout.date)}</div>` : '') +
      print +
      `<section><div class="sechead"><h2 class="serif">${t('eachPhoto')}</h2>` +
      `<span class="count">${t('counts', { p: nums.filter((i) => has(`${i}.jpg`)).length, c: clips })}</span></div>` +
      `<div class="grid">${cells}</div></section>` +
      (times.length ? `<div class="note">${t('saveBefore', { date: dateFor(lang, expiresAt(first, boothTtl(env))) })}</div>` : '') +
      `<p>${escapeHtml(t('help'))}</p>` +
      langLinks(lang) +
      // While files are still coming: ask every 5 s how many are there, reload only when that changes.
      (waiting
        ? `<script>(()=>{let n=${Object.keys(files).length};setInterval(async()=>{try{` +
          `const j=await (await fetch('${BASE}/b/${id}/status.json',{cache:'no-store'})).json();` +
          `if(j.n!==n){n=j.n;location.reload()}}catch(e){}},5000)})()</script>`
        : ''),
  );
}

export async function boothFile(request, env, id, name, now, ctx) {
  const range = request.headers.get('range');
  const object = await env.BOOTH.get(boothKey(id, name), range ? { range: request.headers } : {});
  if (!object) return new Response('Not found', { status: 404 });
  if (isExpired(Number(object.customMetadata?.uploaded), now(), boothTtl(env))) {
    ctx?.waitUntil?.(env.BOOTH.delete(boothKey(id, name)));
    return new Response('Not found', { status: 404 });
  }
  const headers = new Headers({
    'content-type': name.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg',
    'accept-ranges': 'bytes',
    'x-content-type-options': 'nosniff',
    'cache-control': 'private, max-age=3600',
  });
  if (object.httpEtag) headers.set('etag', object.httpEtag);
  if (new URL(request.url).searchParams.get('dl') === '1') {
    headers.set('content-disposition', `attachment; filename="photobooth_${id}_${name}"`);
  }
  const body = request.method === 'HEAD' ? null : object.body;
  if (range && object.range) {
    const offset = object.range.offset ?? 0;
    const length = object.range.length ?? object.size - offset;
    headers.set('content-range', `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set('content-length', String(length));
    return new Response(body, { status: 206, headers });
  }
  headers.set('content-length', String(object.size));
  return new Response(body, { status: 200, headers });
}


/// Deletes every expired file (daily cron).
export async function sweep(env, nowMs) {
  let deleted = 0;
  let cursor;
  do {
    const list = await env.BOOTH.list({ prefix: 'booth/', cursor, include: ['customMetadata'] });
    const old = list.objects
      .filter((o) => isExpired(Number(o.customMetadata?.uploaded ?? o.uploaded?.getTime?.()), nowMs, boothTtl(env)))
      .map((o) => o.key);
    if (old.length) {
      await env.BOOTH.delete(old);
      deleted += old.length;
    }
    cursor = list.truncated ? list.cursor : undefined;
  } while (cursor);
  return deleted;
}

export default {
  async fetch(request, env, ctx, now = () => Date.now()) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');
    if (!path.startsWith(`${BASE}/`)) return new Response('Not found', { status: 404 });
    const rest = path.slice(BASE.length);
    const put = rest.match(/^\/api\/booth\/([a-z0-9]+)\/(print\.jpg|layout\.json|[1-6]\.(?:jpg|mp4))$/);
    if (request.method === 'PUT' && put && isValidId(put[1])) return boothPut(request, env, put[1], put[2], now);
    const st = rest.match(/^\/b\/([a-z0-9]+)\/status\.json$/);
    if (st && isValidId(st[1]) && request.method === 'GET') return json({ n: Object.keys(await boothFiles(env, st[1])).length });
    const b = rest.match(/^\/b\/([a-z0-9]+)(?:\/(print\.jpg|[1-6]\.(?:jpg|mp4)))?$/);
    if (b && isValidId(b[1]) && (request.method === 'GET' || request.method === 'HEAD')) {
      return b[2] ? boothFile(request, env, b[1], b[2], now, ctx) : boothView(env, b[1], now, ctx, pickLang(request));
    }
    // Fonts and anything else under /lde/ that is a static asset.
    if (env.ASSETS && (request.method === 'GET' || request.method === 'HEAD')) return env.ASSETS.fetch(request);
    return new Response('Not found', { status: 404 });
  },

  async scheduled(_event, env, ctx) {
    ctx.waitUntil(sweep(env, Date.now()));
  },
};
