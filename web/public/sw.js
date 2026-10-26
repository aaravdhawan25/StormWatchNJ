// StormWatch NJ service worker
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()));

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const tab = event.notification.data && event.notification.data.tab;
  event.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(windows => {
    const open = windows[0];
    if (open) {
      open.postMessage({ type: "open-tab", tab });
      return open.focus();
    }
    return self.clients.openWindow("/");
  }));
});
