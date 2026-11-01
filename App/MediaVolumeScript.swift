import Foundation

/// Runs in WebKit's isolated client world. Merely observing a player never
/// creates an AudioContext or changes its playback route.
enum MediaVolumeScript {
    static let source = #"""
    (() => {
      if (globalThis.__personalBrowserMixer) return;
      const frame = Math.random().toString(36).slice(2) + Date.now().toString(36);
      const items = new Map(), ids = new WeakMap();
      let serial = 0, pending = null, scheduled = false;
      const send = payload => {
        try { window.webkit.messageHandlers.browserAudioSources.postMessage({frame, ...payload}); } catch (_) {}
      };
      const reason = el => {
        if (el.mediaKeys || el.webkitKeys) return 'DRM音源は音量調整に対応していません。';
        if (el.srcObject) return 'カメラ・通話・ストリーム音源は音量調整に対応していません。';
        if (el.webkitPresentationMode && el.webkitPresentationMode !== 'inline') return '全画面・PiPを終了してから操作してください。';
        if (document.fullscreenElement) return '全画面を終了してから操作してください。';
        let url;
        try { url = new URL(el.currentSrc || el.src, document.baseURI); } catch (_) { return '音源を再生してから確認してください。'; }
        if (!/^https?:$/.test(url.protocol)) return 'Blob・MSEなどの音源は個別ミュートのみ対応します。';
        if (!/\.(mp3|wav|m4a|aac|ogg|oga|mp4|m4v|webm)$/i.test(url.pathname)) return '直接の音声・動画ファイルと確認できないため、個別ミュートのみ対応します。';
        if (!Number.isFinite(el.duration) || el.duration <= 0 || el.readyState < 1) return 'ライブ配信・読込前の音源は個別ミュートのみ対応します。';
        return '';
      };
      const discover = () => {
        document.querySelectorAll('audio,video').forEach(el => {
          if (items.has(ids.get(el)) || items.size >= 64) return;
          const id = ids.get(el) || String(++serial);
          ids.set(el, id); items.set(id, {id, el, context:null, node:null, gain:null, volume:1, error:'', busy:false});
        });
        for (const [id, item] of items) {
          if (!item.el.isConnected && item.el.paused && !item.gain && !item.busy) items.delete(id);
        }
      };
      const snapshot = () => {
        scheduled = false; discover();
        send({sources:[...items.values()].map(item => {
          const el = item.el, unsupported = reason(el);
          return {id:item.id, kind:el.tagName === 'VIDEO' ? 'video' : 'audio',
            label:(el.getAttribute('aria-label') || el.title || '').slice(0,100),
            playing:!el.paused && !el.ended, muted:el.muted,
            volume:item.volume, actualVolume:item.gain ? item.gain.gain.value : 1,
            mode:item.gain ? 'gain' : item.busy ? 'busy' : unsupported ? 'unsupported' : 'candidate',
            reason:item.error || (item.gain ? (item.context.state === 'running' ? '' : '音声制御が停止中です。ページ上で再生し直してください。') : unsupported)};
        })});
      };
      const changed = () => { if (!scheduled) { scheduled = true; setTimeout(snapshot,80); } };
      const removePrompt = () => { pending?.remove(); pending = null; };
      const loadCORS = (el, src) => new Promise((resolve,reject) => {
        const finish = error => { clearTimeout(timeout); el.removeEventListener('canplay',ready); el.removeEventListener('error',failed); error ? reject(error) : resolve(); };
        const ready = () => finish(el.currentSrc === src && el.readyState >= 3 ? null : new Error('changed'));
        const failed = () => finish(new Error('cors'));
        const timeout = setTimeout(() => finish(new Error('timeout')),12000);
        el.addEventListener('canplay',ready); el.addEventListener('error',failed);
        el.load();
      });
      const enable = async item => {
        if (item.busy) return;
        item.error = '';
        if (item.gain) {
          // One explicit in-page action, never an interruption retry loop.
          try { await item.context.resume(); await item.el.play(); } catch (_) { item.error = 'ページの再生ボタンから再生してください。'; }
          changed(); return;
        }
        const why = reason(item.el);
        if (why) { item.error = why; changed(); return; }
        const el = item.el, src = el.currentSrc, oldCORS = el.getAttribute('crossorigin'), position = el.currentTime;
        let context = null, reloaded = false;
        item.busy = true; changed();
        try {
          // Called synchronously by a trusted HTML button click to unlock only
          // our own context. Never intercept site AudioContext/play/pause APIs.
          context = new AudioContext();
          await context.resume();
          if (context.state !== 'running') throw new Error('gesture');
          el.crossOrigin = oldCORS === 'use-credentials' ? 'use-credentials' : 'anonymous';
          reloaded = true;
          await loadCORS(el,src);
          if (reason(el) || el.currentSrc !== src) throw new Error('changed');
          // A successful CORS-mode reload is essential: routing a tainted
          // resource directly would irreversibly replace its audio by silence.
          const gain = context.createGain(), node = context.createMediaElementSource(el);
          item.context = context; item.node = node; item.gain = gain;
          gain.gain.value = 1; node.connect(gain); gain.connect(context.destination);
          context.addEventListener('statechange',changed);
          if (Number.isFinite(position) && position > 0) el.currentTime = Math.min(position,el.duration);
          try { await el.play(); } catch (_) { item.error = '制御は有効です。ページの再生ボタンで再生してください。'; }
        } catch (_) {
          if (!item.gain) {
            if (context) { try { await context.close(); } catch (_) {} }
            if (reloaded) {
              if (oldCORS === null) el.removeAttribute('crossorigin'); else el.setAttribute('crossorigin',oldCORS);
              // Restore the original resource loader, without silently playing
              // after a failed CORS check. The user can restart the player.
              el.addEventListener('loadedmetadata', () => {
                if (Number.isFinite(position) && position > 0 && Number.isFinite(el.duration)) {
                  try { el.currentTime = Math.min(position,el.duration); } catch (_) {}
                }
              }, {once:true});
              el.load();
            }
            item.error = 'CORS・サイト側の制御などで有効化できませんでした。元の読込方式に戻しました。ページから再生してください。';
          } else { item.error = '制御音源が停止しました。ページを再読込すると元の再生方式に戻せます。'; }
        } finally { item.busy = false; changed(); }
      };
      const prompt = item => {
        removePrompt();
        if (innerWidth < 220 || innerHeight < 130) { item.error = '埋込プレーヤーの表示領域が小さすぎます。元サイトを開いて操作してください。'; changed(); return; }
        const box = document.createElement('div');
        box.style.cssText = 'position:fixed;z-index:2147483647;left:8px;right:8px;top:8px;padding:14px;border:1px solid #888;border-radius:12px;background:#202124;color:white;font:14px -apple-system;box-shadow:0 2px 14px #0008';
        const text = document.createElement('p'); text.textContent = item.gain ? 'この音源の音声制御を再開します。' : 'この音源だけをCORS付きで読み直し、音量制御を有効にします。一時的な停止や再生位置のずれが起きる場合があります。';
        const start = document.createElement('button'); start.textContent = item.gain ? '制御音源を再生' : '読み直して再生して有効化';
        const cancel = document.createElement('button'); cancel.textContent = 'キャンセル';
        for (const b of [start,cancel]) b.style.cssText = 'min-height:40px;margin:4px;padding:6px 10px;font:14px -apple-system';
        start.addEventListener('click',event => { if (event.isTrusted) { removePrompt(); void enable(item); } });
        cancel.addEventListener('click',removePrompt);
        box.append(text,start,cancel); (document.body || document.documentElement).append(box); pending = box;
      };
      globalThis.__personalBrowserMixer = {command: command => {
        if (!command || command.frame !== frame) return;
        const item = items.get(command.source);
        if (!item) return;
        if (command.action === 'mute' && typeof command.value === 'boolean') item.el.muted = command.value;
        else if (command.action === 'gain' && item.gain && typeof command.value === 'number' && Number.isFinite(command.value)) {
          item.volume = Math.min(1,Math.max(0,command.value));
          item.gain.gain.setTargetAtTime(item.volume,item.context.currentTime,0.03);
        } else if (command.action === 'enable') prompt(item);
        changed();
      }};
      for (const name of ['play','pause','ended','loadedmetadata','volumechange','emptied','webkitpresentationmodechanged']) document.addEventListener(name,changed,true);
      new MutationObserver(changed).observe(document,{subtree:true,childList:true});
      window.addEventListener('pagehide',() => { removePrompt(); send({gone:true}); });
      window.addEventListener('pageshow',snapshot);
      send({ready:true}); snapshot(); setInterval(snapshot,1500);
    })();
    """#
}
