import Foundation

enum AppPromotionScript {
    static let source = #"""
    (() => {
      if (globalThis.__personalBrowserSetAppPromotions) return;
      let enabled = false, timer = null, lastLock = null, dismissed = false, edits = new Map();
      const roots = new Set([document]); let attempted = new WeakSet(), closed = new WeakSet();
      const reddit = /(^|\.)reddit\.com$/i.test(location.hostname) || __PB_TEST_REDDIT__;
      const known = 'xpromo-app-selector,#app-upsell-blocking-bottom-sheet-direct,#configured-xpromo-mweb3x_mid_funnel_blocking_v1_30s,[id^="xpromo-"],.configured-xpromo,.XPromoPopup.m-active,.XPromoPopupRpl.m-active,.XPromoBlockingModal,.XPromoBlockingModalRpl,shreddit-async-loader[paint-group="xpromo"][bundlename="app_selector"]';
      const generic = '.smartbanner,.app-install-banner,[data-testid="app-upsell"],[data-testid="app-upsell-modal"],[data-testid="app-promo-modal"]';
      const post = value => { try { window.webkit.messageHandlers.browserAppPromotions.postMessage(value); } catch (_) {} };
      const visible = el => {
        if (!el.isConnected) return false;
        for (let p = el, depth = 0; p && depth++ < 40; p = p.parentElement || p.getRootNode().host) {
          if (closed.has(p) || p.hidden || getComputedStyle(p).display === 'none' || getComputedStyle(p).visibility === 'hidden') return false;
        }
        return true;
      };
      const schedule = () => { if (!timer) timer = setTimeout(scan,180); };
      const observer = new MutationObserver(schedule);
      const observe = root => { observer.observe(root,{subtree:true,childList:true,attributes:true,attributeFilter:['class','style','open','inert','aria-hidden','aria-modal','hidden']}); };
      observe(document);
      const discover = () => {
        let budget = 4000;
        for (const root of roots) {
          if (root !== document && !root.host.isConnected) { roots.delete(root); continue; }
          const walker = document.createTreeWalker(root,NodeFilter.SHOW_ELEMENT);
          for (let el = walker.nextNode(); el && budget-- > 0; el = walker.nextNode()) {
            if (el.shadowRoot && roots.size < 64 && !roots.has(el.shadowRoot)) { roots.add(el.shadowRoot); observe(el.shadowRoot); }
          }
          if (budget <= 0) break;
        }
      };
      const all = (root, selector) => [...root.querySelectorAll(selector)];
      const appTarget = el => {
        const nodes = [el,...all(el,'a[href]')];
        return nodes.some(a => {
          const href = a.getAttribute('href') || '';
          return /^(reddit:|intent:|itms-apps:)/i.test(href) || /^https:\/\/(apps\.apple\.com|play\.google\.com|reddit\.app\.link|[a-z0-9.-]+\.onelink\.me)\//i.test(href);
        });
      };
      const save = (el, restore = false) => {
        if (!edits.has(el) && edits.size >= 128) return false;
        if (!edits.has(el)) edits.set(el,{style:el.getAttribute('style'),hidden:el.getAttribute('hidden'),restore});
        if (restore) edits.get(el).restore = true;
        return true;
      };
      const safeBrowserButton = el => {
        const label = (el.textContent || el.getAttribute('aria-label') || '').trim().replace(/\s+/g,' ');
        if (!/^(continue (in|on|with) (the )?(browser|web)|use (the )?web version|ブラウザで(続ける|開く|表示)|閉じる|close)$/i.test(label)) return false;
        if (el.tagName === 'A') {
          try { const url = new URL(el.href,location.href); if (!/^https?:$/.test(url.protocol) || url.origin !== location.origin) return false; } catch (_) { return false; }
        }
        return true;
      };
      const hide = el => {
        if (closed.has(el) || !visible(el)) return;
        if (!attempted.has(el)) {
          attempted.add(el);
          const button = all(el,'button,a[href],[role="button"]').find(safeBrowserButton);
          if (button) { button.click(); schedule(); }
        }
        if (!el.isConnected || !visible(el)) { dismissed = true; return; }
        if (!save(el,true)) return;
        if (el.tagName === 'DIALOG' && el.open) { try { el.close(); } catch (_) {} }
        el.style.setProperty('display','none','important'); el.hidden = true;
        edits.get(el).afterStyle = el.getAttribute('style'); edits.get(el).afterHidden = el.getAttribute('hidden');
        closed.add(el); dismissed = true;
      };
      const genuineModal = () => [...roots].some(root => all(root,'dialog[open],[role="dialog"][aria-modal="true"]').some(visible));
      const unlock = () => {
        if (!dismissed || genuineModal()) return;
        for (const el of [document.documentElement,document.body]) {
          if (!el) continue;
          const style = getComputedStyle(el);
          const locks = ['rpl-scroll-lock','scroll-is-blocked','scroll-disabled'].filter(c => el.classList.contains(c));
          if (locks.length || /hidden|clip/.test(style.overflowY) || (el === document.body && style.position === 'fixed')) {
            if (!save(el)) continue; const top = style.position === 'fixed' ? Math.max(0,-parseFloat(style.top) || 0) : 0;
            for (const c of locks) el.classList.remove(c);
            if (/hidden|clip/.test(getComputedStyle(el).overflowY)) {
              el.style.setProperty('overflow-y','auto','important'); el.style.setProperty('touch-action','auto','important');
            }
            if (el === document.body && style.position === 'fixed') { el.style.setProperty('position','static','important'); el.style.removeProperty('top'); if (top) window.scrollTo(0,top); }
          }
        }
        for (const root of roots) for (const el of all(root,'main[inert],[role="main"][inert],shreddit-app[inert],#AppRouter-main-content[inert]')) { if (save(el)) el.removeAttribute('inert'); }
      };
      const reportLock = () => {
        const locked = [document.documentElement,document.body].some(el => el && (/hidden|clip/.test(getComputedStyle(el).overflowY) || getComputedStyle(el).position === 'fixed')) || genuineModal();
        if (lastLock !== locked) { lastLock = locked; post(locked); }
      };
      function scan() {
        timer = null; discover();
        if (enabled) {
          let budget = 32;
          for (const root of roots) {
            for (const el of all(root,generic)) { if (!closed.has(el) && budget-- > 0 && appTarget(el)) hide(el); }
            if (reddit) {
              for (const el of all(root,known)) { if (!closed.has(el) && budget-- > 0) hide(el); }
              for (const el of all(root,'shreddit-experience-tree')) { if (!closed.has(el) && budget-- > 0 && appTarget(el)) hide(el); }
            }
          }
          unlock();
        }
        reportLock();
      }
      globalThis.__personalBrowserSetAppPromotions = value => {
        enabled = value === true;
        if (!enabled) {
          // Restore only our unchanged component edits. Do not re-lock the
          // body/main or overwrite changes the site made after dismissal.
          for (const [el, before] of edits) if (before.restore) for (const [attr,key,after] of [['style','style','afterStyle'],['hidden','hidden','afterHidden']]) {
            if (el.getAttribute(attr) !== before[after]) continue;
            if (before[key] === null) el.removeAttribute(attr); else el.setAttribute(attr,before[key]);
          }
          edits.clear(); dismissed = false; attempted = new WeakSet(); closed = new WeakSet();
        }
        schedule();
      };
      post('ready'); document.addEventListener('DOMContentLoaded',schedule); window.addEventListener('pageshow',() => { post('ready'); schedule(); });
      window.addEventListener('resize',schedule); setInterval(schedule,2500); schedule();
    })();
    """#
}
