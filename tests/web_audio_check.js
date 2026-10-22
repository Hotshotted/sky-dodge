// Plays the exported web build in headless Chromium and checks that sound really comes out of it.
//   node tests/web_audio_check.js <dir of the export> [chrome path]
// The page is started with a phone-like autoplay policy (no sound until a tap). The browser's audio graph is watched from
// outside: every connection to the speakers also feeds an analyser, so a silent game (a suspended context, streams that never
// start, a muted bus) shows up as a flat line. Exits 1 on silence, printing what it saw.
const http = require('http'), fs = require('fs'), path = require('path');
let chromium;
try { chromium = require('playwright-core').chromium; } catch (e) { chromium = require('playwright').chromium; }
const dir = path.resolve(process.argv[2] || 'build/web');
const chrome = process.argv[3] || process.env.CHROME_PATH || undefined;
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  let p = path.join(dir, decodeURIComponent(req.url.split('?')[0]));
  if (p.endsWith('/')) p += 'index.html';
  fs.readFile(p, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
    res.end(data);
  });
});
const hook = () => {
  window.__a = { ctxs: [], starts: 0, peak: 0, nodes: 0, errors: [], destConnects: 0, buffers: [], worklets: [] };
  const AC = window.AudioContext || window.webkitAudioContext;
  const probes = new WeakMap();
  const origConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    try {
      if (dest && dest === this.context.destination && !probes.has(this.context)) {
        const an = this.context.createAnalyser();
        an.fftSize = 2048;
        probes.set(this.context, an);
        window.__a.analyser = an;
      }
      if (dest && dest === this.context.destination && probes.has(this.context)) {
        window.__a.destConnects++;
        origConnect.call(this, probes.get(this.context));
      }
      window.__a.nodes++;
    } catch (e) { window.__a.errors.push(String(e)); }
    return origConnect.call(this, dest, ...rest);
  };
  const origStart = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) {
    window.__a.starts++;
    try {
      if (window.__a.buffers.length < 6 && this.buffer) {
        const d = this.buffer.getChannelData(0); let m = 0;
        for (let i = 0; i < d.length; i += 7) m = Math.max(m, Math.abs(d[i]));
        window.__a.buffers.push({ len: this.buffer.length, peak: +m.toFixed(3), loop: this.loop });
      }
    } catch (e) {}
    return origStart.apply(this, a);
  };
  function Wrapped(...args) { const c = new AC(...args); window.__a.ctxs.push(c); return c; }
  Wrapped.prototype = AC.prototype;
  window.AudioContext = Wrapped;
  window.webkitAudioContext = Wrapped;
  setInterval(() => {
    const an = window.__a.analyser;
    if (!an) return;
    const buf = new Float32Array(an.fftSize);
    an.getFloatTimeDomainData(buf);
    for (const v of buf) window.__a.peak = Math.max(window.__a.peak, Math.abs(v));
  }, 50);
};
(async () => {
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;
  const browser = await chromium.launch({ executablePath: chrome, args: ['--autoplay-policy=document-user-activation-required', '--use-fake-ui-for-media-stream', '--no-sandbox', '--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true });
  await page.addInitScript(hook);
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  page.on('pageerror', (e) => logs.push('PAGEERROR ' + e.message));
  await page.goto('http://127.0.0.1:' + port + '/index.html');
  // the web loading page goes away when the engine has started; the game's own start-up screen (the pre-warm) follows
  await page.waitForSelector('#status', { state: 'detached', timeout: 150000 });
  await page.waitForTimeout(20000);
  const before = await page.evaluate(() => ({ states: window.__a.ctxs.map((c) => c.state), starts: window.__a.starts, peak: window.__a.peak }));
  await page.touchscreen.tap(195, 420);   // the first tap (browsers keep the sound off until one)
  await page.waitForTimeout(500);
  await page.touchscreen.tap(195, 700);
  const t0 = Date.now();
  while (Date.now() - t0 < 30000) {
    const pk = await page.evaluate(() => window.__a.peak);
    if (pk > 0.002) break;
    await page.waitForTimeout(500);
  }
  await page.waitForTimeout(1500);
  const after = await page.evaluate(() => ({ states: window.__a.ctxs.map((c) => c.state), starts: window.__a.starts, peak: window.__a.peak, nodes: window.__a.nodes, destConnects: window.__a.destConnects, hasAnalyser: !!window.__a.analyser, buffers: window.__a.buffers, errors: window.__a.errors, sampleRate: window.__a.ctxs[0] && window.__a.ctxs[0].sampleRate }));
  const report = { before, after, logs: logs.slice(-12) };
  console.log(JSON.stringify(report, null, 1));
  fs.writeFileSync(path.join(dir, 'audio_report.json'), JSON.stringify(report, null, 1));
  await browser.close();
  server.close();
  const ok = after.states.length > 0 && after.states.every((s) => s === 'running') && after.peak > 0.002;
  if (!ok) { console.error('AUDIO CHECK FAILED: the page made no sound (peak ' + after.peak + ', contexts ' + JSON.stringify(after.states) + ')'); process.exit(1); }
  console.log('AUDIO CHECK PASSED: peak ' + after.peak.toFixed(3));
})().catch((e) => { console.error(e); process.exit(2); });
