// 꽁캠 서비스 워커: 같은 사이트 파일만 다룬다. 페이지와 모델은 항상 새로 받고, 인터넷이 끊기면 마지막으로 받은 것을 쓴다.
const CACHE = 'ggongcam-v1';
self.addEventListener('install', e => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) return;
  const immutable = url.pathname.startsWith('/vendor/') || url.pathname.startsWith('/icons/');
  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    if (immutable) {
      const hit = await cache.match(req);
      if (hit) return hit;
    }
    try {
      const res = await fetch(req);
      if (res.ok && res.type === 'basic') cache.put(req, res.clone()).catch(() => {});
      return res;
    } catch (err) {
      const hit = await cache.match(req, {ignoreSearch: true});
      if (hit) return hit;
      throw err;
    }
  })());
});
