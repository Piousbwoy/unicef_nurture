'use strict';
// Application shell only. SQLite's SharedWorker and database are untouched.
const root = new URL('./', self.location.href);
const indexCache = 'carebridge-shell-index-v1';
const manifestUrl = new URL('offline_shell.json', root).href;
const shellRevision = '__SHELL_REVISION__';
const shellCache = `carebridge-shell-${shellRevision}`;
async function digest(data) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', data)),
    value => value.toString(16).padStart(2, '0')).join('');
}
self.addEventListener('install', event => event.waitUntil((async () => {
  const response = await fetch(manifestUrl, {cache: 'no-store'});
  if (!response.ok) throw new Error('Offline shell manifest missing');
  const manifest = await response.json();
  if (manifest.schema !== 1 || manifest.revision !== shellRevision || !manifest.files.length) throw new Error('Invalid shell manifest');
  const name = `carebridge-shell-${manifest.revision}`;
  const cache = await caches.open(name);
  for (const file of manifest.files) {
    const url = new URL(file.name, root);
    if (url.origin !== root.origin || !url.href.startsWith(root.href) ||
        file.name.includes('..') || file.name.endsWith('.onnx')) throw new Error('Invalid shell path');
    const resource = await fetch(url, {cache: 'no-store'});
    if (!resource.ok) throw new Error('Incomplete shell');
    const bytes = await resource.clone().arrayBuffer();
    if (bytes.byteLength !== file.bytes || await digest(bytes) !== file.sha256) throw new Error('Shell integrity failed');
    await cache.put(url, resource);
  }
  await cache.put(manifestUrl, new Response(JSON.stringify({name, manifest})));
  // Keep older shells for open clients; do not force an active session to reload.
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  const info = await (await caches.open(shellCache)).match(manifestUrl);
  if (!info) throw new Error('Incomplete shell');
  await (await caches.open(indexCache)).put(manifestUrl, info);
  await self.clients.claim();
})()));
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== root.origin) return;
  // Never store API responses, patient records, or arbitrary navigation data.
  event.respondWith((async () => {
    const infoResponse = await (await caches.open(shellCache)).match(manifestUrl);
    if (infoResponse) {
      const info = await infoResponse.json();
      const cache = await caches.open(info.name);
      const key = request.mode === 'navigate' ? new URL('index.html', root).href : request.url;
      const hit = await cache.match(key);
      if (hit) return hit;
    }
    return fetch(request);
  })());
});
