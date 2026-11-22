import Foundation

enum BackgroundAudioScript {
    // Observe page-authored pause calls without suppressing or changing them.
    // The event only cancels recovery; it cannot grant playback or send data.
    static let pauseIntent = #"""
    (() => {
      const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'pause');
      if (!descriptor || typeof descriptor.value !== 'function') return;
      const original = descriptor.value;
      Object.defineProperty(HTMLMediaElement.prototype, 'pause', {...descriptor, value: function(...args) {
        if (this instanceof HTMLMediaElement) this.dispatchEvent(new Event('__personalBrowserPauseIntent'));
        return Reflect.apply(original, this, args);
      }});
    })();
    """#

    static let source = #"""
    (() => {
      if (globalThis.__personalBrowserBackgroundAudio) return;
      const doc = crypto.randomUUID ? crypto.randomUUID() : Array.from(crypto.getRandomValues(new Uint8Array(16)), x => x.toString(16).padStart(2, '0')).join('');
      const ids = new WeakMap(), eligible = new WeakSet();
      let sequence = 0, enabled = false, foreground = true, timer = null, target = null, previousType = null;
      const players = () => Array.from(document.querySelectorAll('video')).slice(0, 32);
      const id = v => { if (!ids.has(v)) ids.set(v, String(++sequence)); return ids.get(v); };
      const pip = v => v.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === v;
      const audible = v => !v.paused && !v.ended && !v.muted && v.volume > 0 && v.readyState >= 2 && !v.srcObject && !pip(v);
      const send = value => { try { webkit.messageHandlers.browserBackgroundAudio.postMessage({document:doc, ...value}); } catch (_) {} };
      function inventory() {
        if (!enabled || !foreground) return;
        const videos = players().map(v => {
          const r = v.getBoundingClientRect(), css = getComputedStyle(v);
          const area = Math.max(0, Math.min(innerWidth,r.right)-Math.max(0,r.left)) * Math.max(0,Math.min(innerHeight,r.bottom)-Math.max(0,r.top));
          return {id:id(v), playing:audible(v), area:css.display !== 'none' && css.visibility === 'visible' && Number(css.opacity) > 0 ? area : 0};
        });
        send({event:'inventory', videos});
      }
      function audioPolicy(on) {
        // Restore only our override, and leave capture/record sessions alone.
        if (window !== top || !navigator.audioSession) return;
        try {
          const s = navigator.audioSession;
          if (on && s.type !== 'play-and-record') {
            if (previousType === null) previousType = s.type;
            s.type = 'playback';
          } else if (!on && previousType !== null) {
            if (s.type === 'playback') s.type = previousType;
            previousType = null;
          }
        } catch (_) {}
      }
      function cancel() {
        if (target) { target.cancelled = true; send({event:'cancel', token:target.token}); }
      }
      function valid(t) {
        return t && t.video.isConnected && t.source === (t.video.currentSrc || t.video.src) && !t.video.srcObject && !t.video.ended && !t.video.muted && t.video.volume > 0 && !pip(t.video);
      }
      function configure(on, visible) {
        enabled = on; foreground = visible;
        clearInterval(timer); timer = null;
        if (visible || !on) { target = null; audioPolicy(false); }
        if (on && visible) { inventory(); timer = setInterval(inventory, 750); }
      }
      globalThis.__personalBrowserBackgroundAudio = {
        get prefersPlayback() { return previousType !== null; },
        configure,
        policy:audioPolicy,
        arm(documentID, videoID, token) {
          if (!enabled || doc !== documentID) return;
          const v = players().find(v => id(v) === videoID);
          const transitionPause = v && document.hidden && eligible.has(v) && v.paused && !v.ended && !v.muted && v.volume > 0 && !v.srcObject && !pip(v);
          if (!v || (!audible(v) && !transitionPause)) { send({event:'cancel',token}); return; }
          target = {video:v, source:v.currentSrc || v.src, token, cancelled:false, requested:false, deadline:performance.now()+3000};
          audioPolicy(true);
          if (transitionPause) { target.requested = true; send({event:'recover',token}); }
        },
        command(documentID, token, action) {
          if (doc !== documentID || target?.token !== token || !valid(target)) return;
          const t = target, v = t.video;
          if (action === 'pause') { cancel(); v.pause(); return; }
          if (action === 'recover') {
            if (foreground || !document.hidden || t.cancelled || performance.now() > t.deadline || !v.paused) return;
          } else if (action !== 'play') return;
          // Explicit remote Play is permitted. Recovery is bounded by both
          // the native transition budget and this exact document/player token.
          if (v.paused) v.play().catch(() => { cancel(); });
        },
        stop() { cancel(); target = null; audioPolicy(false); }
      };
      document.addEventListener('__personalBrowserPauseIntent', e => {
        if (e.target instanceof HTMLVideoElement) eligible.delete(e.target);
        if (e.target === target?.video) cancel();
      }, true);
      for (const event of ['play','playing','pause','ended','emptied','volumechange','webkitpresentationmodechanged']) {
        document.addEventListener(event, e => {
          if (!(e.target instanceof HTMLVideoElement)) return;
          if (event === 'play' || event === 'playing') eligible.add(e.target);
          if ((event === 'pause' && !document.hidden) || event === 'ended' || event === 'emptied') eligible.delete(e.target);
          const t = target;
          if (e.target === t?.video) {
            if (!valid(t) || event === 'emptied') cancel();
            if (event === 'pause' && !foreground && document.hidden && !t.cancelled && !t.requested && performance.now() <= t.deadline) {
              t.requested = true; send({event:'recover',token:t.token});
            }
          }
          inventory();
        }, true);
      }
      window.addEventListener('pagehide', () => { cancel(); target = null; audioPolicy(false); });
      const ready = () => send({event:'ready'});
      window.addEventListener('pageshow', ready); ready();
    })();
    """#
}
