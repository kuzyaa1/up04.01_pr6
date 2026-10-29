{{flutter_js}}
{{flutter_build_config}}

// Local coursework previews must use the current build, including API fixes.
(async () => {
  if (location.hostname === 'localhost' || location.hostname === '127.0.0.1') {
    if ('serviceWorker' in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations
        .filter(r => [r.active, r.waiting, r.installing]
          .some(w => w && new URL(w.scriptURL).pathname.endsWith('/flutter_service_worker.js')))
        .map(r => r.unregister()));
    }
    if ('caches' in window) {
      await Promise.all(['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']
        .map(name => caches.delete(name)));
    }
  }
  try {
    await _flutter.loader.load();
  } catch (error) {
    window.focusFrameLoadError?.();
    console.error('FocusFrame failed to initialize', error);
  }
})();
