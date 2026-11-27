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
    private func update() { tab?.setPageFullscreen(expanded.contains(where: { documents[$0]?.isMainFrame == true })) }
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
        for (let p = document; p; p = Object.getPrototypeOf(p)) {
          const d = Object.getOwnPropertyDescriptor(p, name); if (d) return d;
        }
      };
      const originalElement = descriptor('fullscreenElement'), originalEnabled = descriptor('fullscreenEnabled') || descriptor('webkitFullscreenEnabled');
      let state = null;
      let ancestorAllowed = window===top ? true : null;
      const permissionRequests = [];
      function localAllowed() {
        try {
          const policy=document.permissionsPolicy || document.featurePolicy;
          if(policy?.allowsFeature && !policy.allowsFeature('fullscreen'))return false;
          if(originalEnabled?.get && !originalEnabled.get.call(document))return false;
        } catch (_) { return false; }
        return true;
      }
      function frameAllowed(source) {
        if(!localAllowed() || ancestorAllowed===false)return false;
        if(ancestorAllowed===null)return null;
        const frame=[...document.querySelectorAll('iframe,frame')].find(f=>f.contentWindow===source);
        if(!frame)return false;
        let origin='';try{origin=new URL(frame.src||'about:blank',location.href).origin;}catch(_){}
        const directive=(frame.allow||'').split(';').map(x=>x.trim()).find(x=>/^fullscreen(?:\s|$)/i.test(x));
        if(directive!==undefined) {
          const list=directive.split(/\s+/).slice(1);
          if(list.includes("'none'"))return false;
          return list.length===0 || list.includes('*') || list.includes("'src'") ||
            (list.includes("'self'") && origin===location.origin) || list.includes(origin);
        }
        return frame.allowFullscreen || origin===location.origin || !frame.src || frame.hasAttribute('srcdoc');
      }
      function answerPermission(source, token) {
        const allowed=frameAllowed(source);
        if(allowed===null) { if(permissionRequests.length<64)permissionRequests.push({source,token});return; }
        source.postMessage({kind:'personal-browser-fullscreen-permission',token,allowed},'*');
      }
      function capability() { return localAllowed() && ancestorAllowed!==false; }
      const send = value => { try { webkit.messageHandlers.browserQuietFullscreen.postMessage({document:id,...value}); } catch (_) {} };
      const relay = active => { if (window !== top) parent.postMessage({kind:'personal-browser-fullscreen',active}, '*'); };
      const notify = element => {
        (element?.isConnected ? element : document).dispatchEvent(new Event('fullscreenchange',{bubbles:true}));
        (element?.isConnected ? element : document).dispatchEvent(new Event('webkitfullscreenchange',{bubbles:true}));
      };
      const restore = (element, name, value) => value === null ? element.removeAttribute(name) : element.setAttribute(name,value);
      const inPiP = video => video && (video.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === video);
      const hasPiP = s => s.childPiP || inPiP(s.video) ||
        (document.pictureInPictureElement && s.element.contains(document.pictureInPictureElement)) ||
        [...s.element.querySelectorAll('video')].some(inPiP);
      function holdForPiP(s) {
        if(!s.pipHeld)s.presentationGeneration=(s.presentationGeneration||0)+1;
        if(!s.pipHeld && window!==top)parent.postMessage({kind:'personal-browser-fullscreen',active:true,pip:true},'*');
        s.pipHeld=true; clearTimeout(s.timer);
        // No fullscreenchange, style/popover restoration or native resize
        // while iOS is taking the original video's presentation layer.
      }
      function finishAfterPresentation(s) {
        const generation=s.presentationGeneration||0;
        requestAnimationFrame(()=>{
          if(state!==s || (s.presentationGeneration||0)!==generation)return;
          if(hasPiP(s)){holdForPiP(s);return;}
          if(s.pipHeld && document.hidden)return;
          s.pipHeld=false;finish();
        });
      }
      function finish() {
        const s = state; if (!s) return;
        if(hasPiP(s) || (s.pipHeld && document.hidden)){holdForPiP(s);return;}
        state = null; clearTimeout(s.timer); s.observer?.disconnect();
        s.video?.removeEventListener('webkitbeginfullscreen',s.began);
        s.video?.removeEventListener('webkitendfullscreen',s.ended);
        if(s.modeChanged) {
          const owner=s.native?s.video:document;
          owner.removeEventListener('webkitpresentationmodechanged',s.modeChanged,!s.native);
          owner.removeEventListener('enterpictureinpicture',s.modeChanged,!s.native);
          owner.removeEventListener('leavepictureinpicture',s.modeChanged,!s.native);
        }
        if(s.toggled)s.element.removeEventListener('toggle',s.toggled);
        if (!s.native) {
          try { if (!s.wasOpen && s.element.matches(':popover-open')) s.element.hidePopover(); } catch (_) {}
          restore(s.element,'style',s.style); restore(s.element,'popover',s.popover);
          s.sheet?.remove(); window.scrollTo(s.x,s.y);
          requestAnimationFrame(()=>requestAnimationFrame(()=>{if(!state)window.scrollTo(s.x,s.y);}));
          send({active:false}); relay(false);
        }
        restore(s.element,key,s.marker);
        if (s.entered) notify(s.element);
        s.resolveExit?.();
        if (!s.entered) s.reject?.(new DOMException('Fullscreen ended','AbortError'));
      }
      function exit() {
        const s = state; if (!s) return Promise.resolve();
        // PiP is owned by WebKit/iOS. Ending our fullscreen bookkeeping must
        // not issue a legacy exit command against that same native player.
        if (hasPiP(s) || (s.pipHeld && document.hidden)) { holdForPiP(s); return Promise.resolve(); }
        if (s.pipHeld) { finishAfterPresentation(s); return Promise.resolve(); }
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
      function enter(element, child = null, forceWindow = false) {
        if (!(element instanceof Element) || !element.isConnected || element.ownerDocument !== document)
          return Promise.reject(new TypeError('Disconnected fullscreen element'));
        if (document.hidden || !capability() || ancestorAllowed!==true)
          return Promise.reject(new DOMException('Fullscreen is not permitted','NotAllowedError'));
        if (!child && navigator.userActivation && !navigator.userActivation.isActive)
          return Promise.reject(new DOMException('User activation is required','NotAllowedError'));
        if (state) return state.element===element ? Promise.resolve() : Promise.reject(new DOMException('Already fullscreen','InvalidStateError'));
        const candidates = element instanceof HTMLVideoElement ? [element] : [...element.querySelectorAll('video')];
        const score=v=>{const r=v.getBoundingClientRect(),css=getComputedStyle(v);return css.display==='none'||css.visibility==='hidden'?0:Math.max(0,Math.min(innerWidth,r.right)-Math.max(0,r.left))*Math.max(0,Math.min(innerHeight,r.bottom)-Math.max(0,r.top));};
        const video = forceWindow ? undefined : candidates.filter(v=>v.webkitSupportsFullscreen && typeof v.webkitEnterFullscreen==='function' && (v===element || score(v)>0))
          .sort((a,b)=>score(b)-score(a)||Number(a.paused)-Number(b.paused))[0];
        const s = state = {element,child,video,entered:false,native:!!video,
          marker:element.getAttribute(key),style:element.getAttribute('style'),popover:element.getAttribute('popover'),
          wasOpen:typeof element.showPopover==='function' && element.matches(':popover-open'),x:scrollX,y:scrollY};
        if (video) return new Promise((resolve,reject) => {
          s.reject=reject;
          s.began=()=>{ if(state!==s || s.entered)return; if(hasPiP(s)){holdForPiP(s);return;} s.entered=true;element.setAttribute(key,'active');clearTimeout(s.timer);notify(element);resolve(); };
          s.ended=()=>{ if(state===s)finishAfterPresentation(s); };
          s.modeChanged=()=>{
            if(state!==s)return;
            if(inPiP(video))holdForPiP(s);
            else if(s.pipHeld && video.webkitPresentationMode==='fullscreen') {
              s.pipHeld=false;s.presentationGeneration=(s.presentationGeneration||0)+1;
            }
            else if(s.pipHeld)finishAfterPresentation(s);
          };
          video.addEventListener('webkitbeginfullscreen',s.began);
          video.addEventListener('webkitendfullscreen',s.ended);
          video.addEventListener('webkitpresentationmodechanged',s.modeChanged);
          video.addEventListener('enterpictureinpicture',s.modeChanged);
          video.addEventListener('leavepictureinpicture',s.modeChanged);
          s.timer=setTimeout(()=>{ if(state===s && !s.entered)finish(); },10000);
          try { video.webkitEnterFullscreen(); } catch(error) { s.reject=null;finish();enter(element,child,true).then(resolve,reject); }
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
          s.modeChanged=event=>{
            if(state!==s || (!element.contains(event.target) && !hasPiP(s)))return;
            if(hasPiP(s))holdForPiP(s);
            else if(s.pipHeld)finishAfterPresentation(s);
          };
          document.addEventListener('webkitpresentationmodechanged',s.modeChanged,true);
          document.addEventListener('enterpictureinpicture',s.modeChanged,true);
          document.addEventListener('leavepictureinpicture',s.modeChanged,true);
          s.entered=true;send({ready:true});send({active:true});relay(true);notify(element);
          return Promise.resolve();
        } catch(error) { finish(); return Promise.reject(error); }
      }
      // WebKit versions may expose prefixed methods on a more specific
      // prototype. Cover those own properties as well as Element's methods.
      for(const prototype of [Element.prototype,HTMLElement.prototype,SVGElement.prototype,HTMLMediaElement.prototype,HTMLVideoElement.prototype,HTMLIFrameElement.prototype])
        for(const name of ['requestFullscreen','webkitRequestFullscreen','webkitRequestFullScreen'])
          if(prototype===Element.prototype || Object.hasOwn(prototype,name))
            Object.defineProperty(prototype,name,{configurable:true,writable:true,value:function(){return enter(this);}});
      for(const name of ['exitFullscreen','webkitExitFullscreen','webkitCancelFullScreen'])
        Object.defineProperty(Document.prototype,name,{configurable:true,writable:true,value:exit});
      for(const name of ['fullscreenElement','webkitFullscreenElement','webkitCurrentFullScreenElement'])
        Object.defineProperty(Document.prototype,name,{configurable:true,get(){return state?.entered ? state.element : originalElement?.get?.call(this) ?? null;}});
      for(const name of ['fullscreen','webkitIsFullScreen'])
        Object.defineProperty(Document.prototype,name,{configurable:true,get(){return !!state?.entered;}});
      // Disabling native Element Fullscreen can remove its IDL members.
      // Keep page feature detection and event-handler properties functional.
      for(const name of ['fullscreenEnabled','webkitFullscreenEnabled'])
        Object.defineProperty(Document.prototype,name,{configurable:true,get:capability});
      for(const prototype of [Document.prototype,Element.prototype])
        for(const name of ['onfullscreenchange','onwebkitfullscreenchange']) {
          if(name in prototype)continue;
          const handlers=new WeakMap(),type=name.slice(2);
          Object.defineProperty(prototype,name,{configurable:true,get(){return handlers.get(this)||null;},set(value){
            const old=handlers.get(this);if(old)this.removeEventListener(type,old);
            if(typeof value==='function'){handlers.set(this,value);this.addEventListener(type,value);}else handlers.delete(this);
          }});
        }
      addEventListener('message',event=>{
        if(event.data?.kind==='personal-browser-fullscreen-permission-request') {
          if(typeof event.data.token==='string' && event.data.token.length<=64)answerPermission(event.source,event.data.token);
          return;
        }
        if(event.data?.kind==='personal-browser-fullscreen-permission') {
          if(window!==top && event.source===parent && event.data.token===id && typeof event.data.allowed==='boolean') {
            ancestorAllowed=event.data.allowed;
            for(const request of permissionRequests.splice(0))answerPermission(request.source,request.token);
          }
          return;
        }
        if(event.data?.kind==='personal-browser-fullscreen-exit' && event.source===parent) { exit().catch(()=>{});return; }
        if(event.data?.kind!=='personal-browser-fullscreen')return;
        const frame=[...document.querySelectorAll('iframe,frame')].find(f=>f.contentWindow===event.source);
        if(!frame)return;
        if(state?.child===event.source && event.data.pip===true){state.childPiP=true;holdForPiP(state);return;}
        if(event.data.active===false) { if(state?.child===event.source){state.childPiP=false;state.pipHeld=false;finishAfterPresentation(state);}return; }
        if(event.data.active!==true || (navigator.userActivation && !navigator.userActivation.isActive))return;
        if(frameAllowed(event.source)!==true)return;
        enter(frame,event.source).catch(()=>{});
      });
      document.addEventListener('keydown',event=>{if(event.key==='Escape')exit().catch(()=>{});},true);
      document.addEventListener('visibilitychange',()=>{
        if(!document.hidden && state?.pipHeld && !hasPiP(state))finishAfterPresentation(state);
      });
      document.addEventListener('__personalBrowserRequestQuietFullscreen',event=>{
        if(event.target instanceof HTMLVideoElement)enter(event.target).catch(()=>{});
      },true);
      addEventListener('pagehide',()=>{if(state && (hasPiP(state)||state.pipHeld))holdForPiP(state);else if(state?.native)exit().catch(()=>{});else finish();});
      Object.defineProperty(globalThis,'__personalBrowserQuietFullscreen',{value:{exit},configurable:false});
      if(window!==top)parent.postMessage({kind:'personal-browser-fullscreen-permission-request',token:id},'*');
      send({ready:true});
    })();
    """#
}
