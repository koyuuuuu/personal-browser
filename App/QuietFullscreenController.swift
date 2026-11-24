import UIKit
import WebKit

/// Routes page fullscreen requests through public video/popover APIs. Never
/// invokes Element Fullscreen, whose WebKit warning has no public off switch.
@MainActor
final class QuietFullscreenController: NSObject, WKScriptMessageHandler {
    private weak var tab: BrowserTab?
    private weak var view: WKWebView?
    private var documents: [String: WKFrameInfo] = [:]
    private var expanded = Set<String>()

    init(tab: BrowserTab, view: WKWebView) {
        self.tab = tab; self.view = view
        super.init()
        let content = view.configuration.userContentController
        content.add(self, contentWorld: .page, name: "browserQuietFullscreen")
        content.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }
    func reset() {
        exit()
        documents.removeAll(); expanded.removeAll(); update()
    }
    func detach() {
        view?.configuration.userContentController.removeScriptMessageHandler(forName: "browserQuietFullscreen", contentWorld: .page)
        reset()
    }
    func exit() {
        let frames = expanded.compactMap { documents[$0] }
        expanded.removeAll(); update() // Native browser controls remain an escape even if page JS is busy.
        guard let view else { return }
        for frame in frames { exitQuietFullscreen(view, frame: frame) }
    }
    private func update() { tab?.setPageFullscreen(!expanded.isEmpty) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view, message.webView === view, let value = message.body as? [String: Any],
              let id = value["document"] as? String, id.count <= 64 else { return }
        if value["ready"] as? Bool == true {
            if documents.count >= 64, documents[id] == nil,
               let stale = documents.keys.first(where: { !expanded.contains($0) }) { documents.removeValue(forKey: stale) }
            if documents[id] != nil || documents.count < 64 { documents[id] = message.frameInfo }
            return
        }
        guard documents[id] != nil, let active = value["active"] as? Bool else { return }
        if active {
            guard UIApplication.shared.applicationState == .active, tab?.mayRecoverAutomatically?() == true else { return }
            expanded.insert(id)
        } else { expanded.remove(id); documents.removeValue(forKey: id) }
        update()
    }

    static let script = #"""
    (() => {
      if (globalThis.__personalBrowserQuietFullscreen) return;
      const id = crypto.randomUUID ? crypto.randomUUID() : Array.from(crypto.getRandomValues(new Uint8Array(16)),x=>x.toString(16).padStart(2,'0')).join(''), key = 'data-personal-browser-fullscreen';
      const descriptor = name => {
        for (let p = Document.prototype; p; p = Object.getPrototypeOf(p)) {
          const d = Object.getOwnPropertyDescriptor(p, name); if (d) return d;
        }
      };
      const originalElement = descriptor('fullscreenElement'), originalEnabled = descriptor('fullscreenEnabled');
      let state = null;
      const send = value => { try { webkit.messageHandlers.browserQuietFullscreen.postMessage({document:id,...value}); } catch (_) {} };
      const relay = active => { if (window !== top) parent.postMessage({kind:'personal-browser-fullscreen',active}, '*'); };
      const notify = () => {
        document.dispatchEvent(new Event('fullscreenchange'));
        document.dispatchEvent(new Event('webkitfullscreenchange'));
      };
      const restore = (element, name, value) => value === null ? element.removeAttribute(name) : element.setAttribute(name,value);
      function finish() {
        const s = state; if (!s) return;
        state = null; clearTimeout(s.timer); s.observer?.disconnect();
        s.video?.removeEventListener('webkitbeginfullscreen',s.began);
        s.video?.removeEventListener('webkitendfullscreen',s.ended);
        if(s.toggled)s.element.removeEventListener('toggle',s.toggled);
        if (!s.native) {
          try { if (!s.wasOpen && s.element.matches(':popover-open')) s.element.hidePopover(); } catch (_) {}
          restore(s.element,'style',s.style); restore(s.element,'popover',s.popover);
          s.sheet?.remove(); window.scrollTo(s.x,s.y);
          requestAnimationFrame(()=>requestAnimationFrame(()=>{if(!state)window.scrollTo(s.x,s.y);}));
          send({active:false}); relay(false);
        }
        restore(s.element,key,s.marker);
        if (s.entered) notify();
        s.resolveExit?.();
        if (!s.entered) s.reject?.(new DOMException('Fullscreen ended','AbortError'));
      }
      function exit() {
        const s = state; if (!s) return Promise.resolve();
        if (s.child) s.child.postMessage({kind:'personal-browser-fullscreen-exit'},'*');
        if (!s.native) { finish(); return Promise.resolve(); }
        if(s.exitPromise)return s.exitPromise;
        s.exitPromise=new Promise((resolve,reject) => {
          s.resolveExit=resolve;
          s.timer=setTimeout(()=>{
            if(state!==s)return;
            if(!s.video.webkitDisplayingFullscreen && s.video.webkitPresentationMode!=='fullscreen')finish();
            else {s.exitPromise=null;reject(new DOMException('Fullscreen exit is pending','AbortError'));}
          },5000);
          try { s.video.webkitExitFullscreen(); }
          catch (error) { clearTimeout(s.timer);s.exitPromise=null;reject(error); }
        });
        return s.exitPromise.catch(error=>{if(state===s)s.exitPromise=null;throw error;});
      }
      function enter(element, child = null) {
        if (!(element instanceof Element) || !element.isConnected || element.ownerDocument !== document)
          return Promise.reject(new TypeError('Disconnected fullscreen element'));
        if (document.hidden || (originalEnabled?.get && !originalEnabled.get.call(document)))
          return Promise.reject(new DOMException('Fullscreen is not permitted','NotAllowedError'));
        if (!child && navigator.userActivation && !navigator.userActivation.isActive)
          return Promise.reject(new DOMException('User activation is required','NotAllowedError'));
        if (state) return state.element===element ? Promise.resolve() : Promise.reject(new DOMException('Already fullscreen','InvalidStateError'));
        const candidates = element instanceof HTMLVideoElement ? [element] : [...element.querySelectorAll('video')];
        const score=v=>{const r=v.getBoundingClientRect(),css=getComputedStyle(v);return css.display==='none'||css.visibility==='hidden'?0:Math.max(0,Math.min(innerWidth,r.right)-Math.max(0,r.left))*Math.max(0,Math.min(innerHeight,r.bottom)-Math.max(0,r.top));};
        const video = candidates.filter(v=>v.webkitSupportsFullscreen && typeof v.webkitEnterFullscreen==='function' && (v===element || score(v)>0))
          .sort((a,b)=>score(b)-score(a)||Number(a.paused)-Number(b.paused))[0];
        const s = state = {element,child,video,entered:false,native:!!video,
          marker:element.getAttribute(key),style:element.getAttribute('style'),popover:element.getAttribute('popover'),
          wasOpen:typeof element.showPopover==='function' && element.matches(':popover-open'),x:scrollX,y:scrollY};
        if (video) return new Promise((resolve,reject) => {
          s.reject=reject;
          s.began=()=>{ if(state!==s || s.entered)return; s.entered=true;element.setAttribute(key,'active');clearTimeout(s.timer);notify();resolve(); };
          s.ended=()=>{ if(state===s)finish(); };
          video.addEventListener('webkitbeginfullscreen',s.began);
          video.addEventListener('webkitendfullscreen',s.ended);
          s.timer=setTimeout(()=>{ if(state===s && !s.entered)finish(); },10000);
          try { video.webkitEnterFullscreen(); } catch(error) { finish(); reject(error); }
        });
        try {
          element.setAttribute(key,'active');
          // Popover uses the CSS top layer without reparenting the original
          // element/video. Preserve source, currentTime, listeners and controls.
          const sheet = s.sheet = document.createElement('style');
          let css = `[${key}="active"]::backdrop{background:black}`;
          for(const styles of [...document.styleSheets]) {
            try { for(const rule of [...styles.cssRules]) {
              if(css.length<262144 && /:fullscreen|:-webkit-full-screen/.test(rule.cssText))
                css += rule.cssText.replace(/:fullscreen\b|:-webkit-full-screen\b/g,`[${key}="active"]`);
            } } catch (_) {}
          }
          sheet.textContent=css; (document.head||document.documentElement).append(sheet);
          const values={position:'fixed',inset:'0',width:'100vw',height:'100dvh','max-width':'none','max-height':'none',margin:'0',padding:'0',border:'0',transform:'none','box-sizing':'border-box','z-index':'2147483647','background-color':'black'};
          for(const [name,value] of Object.entries(values))element.style.setProperty(name,value,'important');
          if(typeof element.showPopover==='function') { element.setAttribute('popover','manual');element.showPopover(); }
          s.toggled=event=>{ if(state===s && event.newState==='closed')finish(); };
          element.addEventListener('toggle',s.toggled);
          s.observer=new MutationObserver(()=>{ if(state===s && !element.isConnected)finish(); });
          s.observer.observe(document,{childList:true,subtree:true});
          s.entered=true;send({ready:true});send({active:true});relay(true);notify();
          return Promise.resolve();
        } catch(error) { finish(); return Promise.reject(error); }
      }
      for(const name of ['requestFullscreen','webkitRequestFullscreen','webkitRequestFullScreen'])
        Object.defineProperty(Element.prototype,name,{configurable:true,writable:true,value:function(){return enter(this);}});
      for(const name of ['exitFullscreen','webkitExitFullscreen','webkitCancelFullScreen'])
        Object.defineProperty(Document.prototype,name,{configurable:true,writable:true,value:exit});
      for(const name of ['fullscreenElement','webkitFullscreenElement'])
        Object.defineProperty(Document.prototype,name,{configurable:true,get(){return state?.entered ? state.element : originalElement?.get?.call(this) ?? null;}});
      for(const name of ['fullscreen','webkitIsFullScreen'])
        Object.defineProperty(Document.prototype,name,{configurable:true,get(){return !!state?.entered;}});
      addEventListener('message',event=>{
        if(event.data?.kind==='personal-browser-fullscreen-exit' && event.source===parent) { exit().catch(()=>{});return; }
        if(event.data?.kind!=='personal-browser-fullscreen')return;
        const frame=[...document.querySelectorAll('iframe,frame')].find(f=>f.contentWindow===event.source);
        if(!frame)return;
        if(event.data.active===false) { if(state?.child===event.source)finish();return; }
        if(event.data.active!==true || (navigator.userActivation && !navigator.userActivation.isActive))return;
        let sameOrigin=false;try{sameOrigin=new URL(frame.src,location.href).origin===location.origin;}catch(_){}
        if(!sameOrigin && !frame.allowFullscreen && !/(^|;)\s*fullscreen(?:\s|;|$)/i.test(frame.allow||''))return;
        enter(frame,event.source).catch(()=>{});
      });
      document.addEventListener('keydown',event=>{if(event.key==='Escape')exit().catch(()=>{});},true);
      document.addEventListener('__personalBrowserRequestQuietFullscreen',event=>{
        if(event.target instanceof HTMLVideoElement)enter(event.target).catch(()=>{});
      },true);
      addEventListener('pagehide',()=>{if(state?.native)exit().catch(()=>{});else finish();});
      Object.defineProperty(globalThis,'__personalBrowserQuietFullscreen',{value:{exit},configurable:false});
      send({ready:true});
    })();
    """#
}
