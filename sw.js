self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });

self.addEventListener('push', function (e) {
  var d = {};
  try { d = e.data ? e.data.json() : {}; } catch (x) { d = { body: e.data ? e.data.text() : '' }; }
  var opts = {
    body: d.body || '',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    dir: 'rtl',
    lang: 'ar',
    data: { url: d.url || '/shop.html' }
  };
  if (d.tag) { opts.tag = d.tag; opts.renotify = true; }
  e.waitUntil(self.registration.showNotification(d.title || 'أوريس', opts));
});

self.addEventListener('notificationclick', function (e) {
  e.notification.close();
  var url = new URL((e.notification.data && e.notification.data.url) || '/shop.html', self.location.origin).href;
  var base = url.split('#')[0];
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      if (c.url.split('#')[0] === base && 'focus' in c) {
        // نفس الصفحة مفتوحة: ركّز عليها وغيّر الـ #hash فقط (بدون إعادة تحميل)
        return c.focus().then(function (w) { return (w && c.url !== url && 'navigate' in w) ? w.navigate(url).catch(function () {}) : w; });
      }
    }
    return self.clients.openWindow(url);
  }));
});
