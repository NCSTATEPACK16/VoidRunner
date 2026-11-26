// Web gate: serves an exported build and plays the title flow in headless Chromium
// (SwiftShader GL), failing on SCRIPT ERROR, SHADER ERROR or an uncaught page error.
//   node tests/web_check.mjs <out_dir> [dist_dir]   (export first: see build.sh)
// Prints the sprite bake, title-up and first-flight times, and screenshots each step.
// Playwright comes from the container's global install, or PW_MODULE if set.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const GLOBAL_PW = '/opt/node22/lib/node_modules/playwright/index.mjs';
const { chromium } = await import(process.env.PW_MODULE
  || (fs.existsSync(GLOBAL_PW) ? GLOBAL_PW : 'playwright'));
const out = process.argv[2] || '.';
const root = path.resolve(process.argv[3] || 'dist');
const CHROME = process.env.PW_CHROMIUM || '/opt/pw-browsers/chromium';
const types = { '.html': 'text/html', '.js': 'application/javascript',
  '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };

fs.mkdirSync(out, { recursive: true });
const srv = http.createServer((q, r) => {
  const rel = decodeURIComponent(q.url.split('?')[0]);
  const f = path.join(root, rel === '/' ? 'index.html' : rel);
  fs.readFile(f, (e, d) => {
    if (e) { r.writeHead(404); r.end(); return; }
    r.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' });
    r.end(d);
  });
}).listen(8765);

const browser = await chromium.launch({
  executablePath: fs.existsSync(CHROME) ? CHROME : undefined,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 960, height: 600 } });
const errors = [];
const t0 = Date.now();
page.on('console', (m) => {
  const t = m.text();
  if (/SCRIPT ERROR|SHADER ERROR/.test(t)) errors.push(t);
  if (/GAME BOOTING|sprite bake|first flight|pointer lock/i.test(t)) console.log('[con]', t.slice(0, 160));
});
// PR C: no page error is ignored any more. The pointer-lock race is fixed (capture
// waits for a live user activation and the shell catches a refusal quietly).
page.on('pageerror', (e) => { errors.push('pageerror: ' + e.message); });
const wait = (ms) => page.waitForTimeout(ms);
const shot = (n) => page.screenshot({ path: `${out}/${n}.png` });

await page.goto('http://127.0.0.1:8765/');
await page.waitForFunction(() => {
  const o = document.getElementById('vr-loading');
  return o && (o.hidden || getComputedStyle(o).display === 'none'
    || getComputedStyle(o).opacity === '0' || o.classList.contains('vr-gone'));
}, null, { timeout: 240000 });
console.log('title up', Date.now() - t0, 'ms');
await wait(3000);
await page.mouse.click(480, 300);
// the title flow (option B): notice -> PRESS ENTER -> card row -> NEW GAME window
await page.keyboard.press('Enter'); await wait(1500); await shot('1_attract');   // UNDERSTOOD
await page.keyboard.press('Enter'); await wait(1500); await shot('2_cards');     // PRESS ENTER
await page.keyboard.press('Enter'); await wait(1500); await shot('3_new_game');  // NEW GAME
await page.keyboard.press('Enter'); await wait(1500); await shot('4_episode');    // > LAUNCH
await page.keyboard.press('Enter'); await wait(2500); await shot('4_briefing');  // title card -> briefing
await page.keyboard.press('Enter'); await wait(4000);                            // briefing LAUNCH
await page.keyboard.down('Space'); await wait(8000); await page.keyboard.up('Space');
await shot('5_flight');
// Step 7: vrReport() carries the live diagnostics (published every 2 s on web)
const fails = [];
await wait(2500);
const diag = await page.evaluate(() => window.vrBoot && window.vrBoot.diag);
if (diag && diag.fps > 0 && typeof diag.renderer === 'string') console.log('diag ok', JSON.stringify(diag));
else fails.push('diag missing or empty: ' + JSON.stringify(diag));
// review fixes: the GPU is the unmasked one, and FLIGHT uses the page-load clock
const ff = await page.evaluate(() => window.vrBoot.firstFlightMs);
if (!diag || !diag.adapter || /^WebKit WebGL$/.test(diag.adapter)) fails.push('gpu still masked: ' + (diag && diag.adapter));
else console.log('gpu ok', diag.adapter);
if (!diag || Math.abs(diag.first_flight_ms - ff) > 50) fails.push(`flight clocks differ: diag ${diag && diag.first_flight_ms} vs page ${ff}`);
else console.log('flight clock ok', ff, 'ms');
// Step 7: a lost WebGL context shows the tap-to-reload screen above everything.
// Errors the engine logs after the context is gone don't count.
const lostAt = errors.length;
await page.evaluate(() => document.getElementById('canvas').getContext('webgl2')
  .getExtension('WEBGL_lose_context').loseContext());
await wait(500);
const onTop = await page.evaluate(() => {
  const el = document.elementFromPoint(480, 300);
  return !!(el && el.closest('#vr-lost')) && window.vrBoot.contextLost >= 1;
});
await shot('6_lost');
if (onTop) console.log('lost screen ok'); else fails.push('lost screen not shown on top');
errors.length = lostAt;
errors.push(...fails);
console.log(errors.length ? errors.join('\n') : 'no script, shader or page errors');
await browser.close();
srv.close();
process.exit(errors.length ? 1 : 0);
