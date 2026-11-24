// Retire the former combined demo worker without touching local learning data.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('zhiban-offline-')).map(k => caches.delete(k)))).then(() => self.registration.unregister())
));
