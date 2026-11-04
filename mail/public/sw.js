// حوات ميل: إشعارات الرسائل الجديدة + فتح التطبيق عند الضغط.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {}); // مطلوب عشان Chrome يعرضه كتطبيق قابل للتثبيت

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data.json(); } catch { d = { title: 'حوات ميل', body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'حوات ميل', {
    body: d.body || '', icon: 'icon-192.png', badge: 'badge-96.png', tag: d.tag, dir: 'auto', lang: 'ar',
    data: { url: d.url || './' },
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = new URL(e.notification.data?.url || './', self.registration.scope).href;
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const w = all.find((c) => c.url.startsWith(self.registration.scope));
    if (w) { await w.focus(); return w.navigate(url); }
    return self.clients.openWindow(url);
  })());
});
