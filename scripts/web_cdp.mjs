// Load a page in headless Chrome over the DevTools protocol and wait for its
// verdict in document.title (#14). `--dump-dom` cannot do this: it runs
// requestAnimationFrame once, and a frame-driven app needs it every frame.
// Headless Chrome also destroys a GPUDevice right after it draws to a canvas
// (plain JS does the same), so test.html runs with ?canvas-lost here.
//
// usage: node scripts/web_cdp.mjs <chrome> <url> [timeout_s]   (Node >= 22: global WebSocket)
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [chrome, url, timeoutS = '90'] = process.argv.slice(2);
const profile = mkdtempSync(join(tmpdir(), 'wgpu-web-'));
const proc = spawn(chrome, [
  '--headless=new', '--no-sandbox', '--disable-gpu-sandbox', `--user-data-dir=${profile}`,
  '--enable-unsafe-webgpu',
  // WEBGPU_ADAPTER=default uses the machine's GPU; swiftshader works anywhere (CI).
  ...(process.env.WEBGPU_ADAPTER === 'default' ? [] : ['--enable-unsafe-swiftshader', '--use-webgpu-adapter=swiftshader']),
  '--remote-debugging-port=0', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
const done = (code) => {
  proc.kill();
  try { rmSync(profile, { recursive: true, force: true }); } catch {}  // Chrome may still be writing it
  process.exit(code);
};
let stage = 'starting chrome', stderr = '';
setTimeout(() => {
  console.log(`web_cdp: timed out (${stage})`);
  if (stage === 'starting chrome') console.log(stderr.slice(-2000));
  done(1);
}, Number(timeoutS) * 1000);

const port = await new Promise((resolve) => {
  let buf = '';
  proc.stderr.on('data', (d) => {
    buf += d;
    stderr = buf;
    const m = buf.match(/DevTools listening on ws:\/\/[^:]+:(\d+)\//);
    if (m) resolve(m[1]);
  });
});
stage = 'opening page';
const target = await (await fetch(`http://127.0.0.1:${port}/json/new?${url}`, { method: 'PUT' })).json();
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));

let id = 0;
const pending = new Map();
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result); pending.delete(msg.id); }
  if (msg.method === 'Runtime.consoleAPICalled')
    console.log('console:', msg.params.args.map((a) => a.value ?? a.description).join(' '));
  if (msg.method === 'Runtime.exceptionThrown')
    console.log('exception:', msg.params.exceptionDetails.exception?.description);
});
const send = (method, params = {}) => new Promise((r) => {
  pending.set(++id, r);
  ws.send(JSON.stringify({ id, method, params }));
});
await send('Runtime.enable');
stage = 'waiting for the page verdict';

for (;;) {
  const r = await send('Runtime.evaluate', {
    expression: 'JSON.stringify([document.title, document.getElementById("log")?.textContent ?? ""])',
    returnByValue: true,
  });
  const [title, log] = JSON.parse(r?.result?.value ?? '["",""]');
  if (title === 'PASS' || title.startsWith('FAIL')) {
    console.log(log);
    console.log('test-web:', title);
    done(title === 'PASS' ? 0 : 1);
  }
  await new Promise((r) => setTimeout(r, 250));
}
