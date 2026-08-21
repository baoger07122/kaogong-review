// 考公笔试复盘系统 — Service Worker
// 策略：联网优先（network-first）。每次打开都向服务器拉取最新 index.html，
// 在线时永远显示最新版本；离线时回退到缓存。彻底解决 iPad「添加到主屏幕」后
// 一直显示旧版的问题。
const CACHE = 'kaogong-cache-v2.3.8';

self.addEventListener('install', (event) => {
  // 直接激活，不等旧页面关闭
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // 清理旧版本缓存
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  // 导航请求（index.html）→ 联网优先，失败回退缓存
  if (req.mode === 'navigate' || req.url.endsWith('/') || req.url.endsWith('index.html')) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then(r => r || fetch(req)))
    );
    return;
  }

  // 其他静态资源：联网优先，并把结果写入缓存
  event.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy));
        return res;
      })
      .catch(() => caches.match(req))
  );
});
