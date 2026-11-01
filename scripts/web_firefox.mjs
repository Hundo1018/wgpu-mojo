// Load a page in headless Firefox through geckodriver (W3C WebDriver over HTTP)
// and wait for its verdict in document.title (#14).
//
// usage: node scripts/web_firefox.mjs <geckodriver> <url> [timeout_s]
import { spawn } from 'node:child_process';

const [gecko, url, timeoutS = '90'] = process.argv.slice(2);
const port = 4400 + Math.floor(Math.random() * 500);
const driver = spawn(gecko, ['--port', String(port)], { stdio: 'ignore' });
const base = `http://127.0.0.1:${port}`;
let session = null;
const done = async (code) => {
  if (session) await fetch(`${base}/session/${session}`, { method: 'DELETE' }).catch(() => {});
  try { driver.kill(); } catch {}  // snap-confined geckodriver may refuse the signal
  process.exit(code);
};
setTimeout(() => { console.log('web_firefox: timed out'); done(1); }, Number(timeoutS) * 1000);

const call = async (method, path, body) => {
  const r = await fetch(base + path, {
    method, headers: { 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return (await r.json()).value;
};
for (let i = 0; i < 100; i++) {
  try { await fetch(base + '/status'); break; } catch { await new Promise((r) => setTimeout(r, 100)); }
}
const s = await call('POST', '/session', { capabilities: { alwaysMatch: {
  'moz:firefoxOptions': {
    args: ['-headless'],
    prefs: { 'dom.webgpu.enabled': true, 'gfx.webgpu.ignore-blocklist': true },
  },
} } });
session = s.sessionId;
if (!session) { console.log('web_firefox: no session', JSON.stringify(s)); await done(1); }
console.log('firefox', s.capabilities.browserVersion);
await call('POST', `/session/${session}/url`, { url });
for (;;) {
  const [title, log] = await call('POST', `/session/${session}/execute/sync`, {
    script: 'return [document.title, document.getElementById("log")?.textContent ?? ""]', args: [],
  });
  if (title === 'PASS' || title.startsWith('FAIL')) {
    console.log(log);
    console.log('test-web (firefox):', title);
    await done(title === 'PASS' ? 0 : 1);
  }
  await new Promise((r) => setTimeout(r, 250));
}
