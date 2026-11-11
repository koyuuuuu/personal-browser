import Foundation

/// Isolated-world metadata only. Never replaces the site's player or playback methods.
enum VideoOrientationScript {
    static func source(enabled: Bool) -> String {
        template.replacingOccurrences(of: "__ENABLED__", with: enabled ? "true" : "false")
    }
    static let template = #"""
    (() => {
      if (globalThis.__personalBrowserVideo) return;
      const documentID = crypto.randomUUID ? crypto.randomUUID() : Array.from(crypto.getRandomValues(new Uint8Array(16)), x => x.toString(16).padStart(2, '0')).join(''), states = new WeakMap();
      let enabled = __ENABLED__, active = true, timer = null, sequence = 0;
      let current = new Map();
      const intersection = new IntersectionObserver(entries => {
        for (const entry of entries) {
          const s = states.get(entry.target);
          if (s) s.area = entry.isIntersecting ? entry.intersectionRect.width * entry.intersectionRect.height : 0;
        }
        report();
      });
      function state(video) {
        if (!states.has(video)) {
          states.set(video, {id: String(++sequence), paused: video.paused && video.currentTime > 0, transition: 0, area: 0, nativeFullscreen: null});
          intersection.observe(video);
          // Native WebKit getters can lag the actual transition. Keep the
          // video's own begin/end events authoritative once observed.
          video.addEventListener('webkitbeginfullscreen', () => { states.get(video).nativeFullscreen = true; report(); });
          video.addEventListener('webkitendfullscreen', () => { states.get(video).nativeFullscreen = false; report(); });
          video.addEventListener('webkitpresentationmodechanged', () => {
            if (video.webkitPresentationMode === 'picture-in-picture') states.get(video).nativeFullscreen = false;
            report();
          });
        }
        return states.get(video);
      }
      function full(video) {
        if (video.webkitPresentationMode === 'picture-in-picture') return false;
        const known = states.get(video)?.nativeFullscreen;
        const element = document.fullscreenElement;
        return known === true || (known == null && !!(video.webkitDisplayingFullscreen || video.webkitPresentationMode === 'fullscreen')) || !!element?.contains(video);
      }
      function inventory() {
        const values = []; current = new Map();
        for (const video of Array.from(document.querySelectorAll('video')).slice(0, 16)) {
          const s = state(video), r = video.getBoundingClientRect(), css = getComputedStyle(video);
          const area = Math.max(0, Math.min(innerWidth, r.right) - Math.max(0, r.left)) * Math.max(0, Math.min(innerHeight, r.bottom) - Math.max(0, r.top));
          current.set(s.id, video);
          values.push({id:s.id, width:video.videoWidth, height:video.videoHeight,
            playing:!video.paused && !video.ended, paused:s.paused || video.ended || (video.paused && video.currentTime > 0),
            fullscreen:full(video), pip:video.webkitPresentationMode === 'picture-in-picture',
            area:css.visibility === 'visible' && css.display !== 'none' && Number(css.opacity) > 0 ? Math.min(area, s.area) : 0,
            supported:!!(video.webkitSupportsFullscreen || video.requestFullscreen)});
        }
        return values;
      }
      function report() {
        if (!enabled || !active) return;
        try { webkit.messageHandlers.browserVideoOrientation.postMessage({document:documentID, videos:inventory()}); } catch (_) {}
      }
      function configure(on, visible) {
        enabled = on; active = visible;
        clearInterval(timer); timer = null;
        if (enabled && active) { report(); timer = setInterval(report, 750); }
      }
      globalThis.__personalBrowserVideo = {
        configure,
        enter(doc, id) {
          if (!enabled || !active || doc !== documentID) return;
          inventory(); const video = current.get(id);
          if (!video || !video.isConnected || full(video) || video.webkitPresentationMode === 'picture-in-picture') return;
          const s = state(video), r = video.getBoundingClientRect();
          if (s.paused || video.ended || (video.paused && video.currentTime > 0) || s.area < 6400 || r.width < 40 || r.height < 40 || r.bottom <= 0 || r.top >= innerHeight) return;
          // One attempt per physical tilt. Keep existing playback untouched;
          // a never-started clip may still require the site's own play gesture.
          s.transition = performance.now() + 1500;
          try {
            if (video.paused) video.play().catch(() => {});
            if (video.webkitSupportsFullscreen && video.webkitEnterFullscreen) video.webkitEnterFullscreen();
            else video.requestFullscreen?.().catch(() => {});
          } catch (_) {}
        }
      };
      for (const name of ['play','pause','loadedmetadata','resize','webkitbeginfullscreen','webkitendfullscreen','webkitpresentationmodechanged','fullscreenchange']) {
        document.addEventListener(name, event => {
          const video = event.target;
          if (video instanceof HTMLVideoElement) {
            const s = state(video);
            if (name === 'play') s.paused = false;
            if (name === 'pause' && performance.now() > s.transition) s.paused = true;
          }
          report();
        }, true);
      }
      addEventListener('pagehide', () => { clearInterval(timer); timer = null; if (enabled) webkit.messageHandlers.browserVideoOrientation.postMessage({document:documentID, videos:[], gone:true}); });
      addEventListener('pageshow', () => configure(enabled, active));
      configure(enabled, active);
    })();
    """#
}
