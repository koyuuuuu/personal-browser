import Foundation

enum PasswordFormScript {
    static let source = #"""
    (() => {
      if (globalThis.__personalBrowserPasswords) return;
      const doc = crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36)+Date.now();
      const ids = new WeakMap(), fields = new Map(), dirty = new WeakSet(), hints = new Map();
      let saveEnabled = globalThis.__personalBrowserSaveOffers !== false;
      let hintsEnabled = globalThis.__personalBrowserAppleHints !== false; let serial = 0, timer = null;
      const roots = () => {
        const result=[document]; let budget=3000;
        for (let i=0;i<result.length && i<32;i++) {
          const walker=document.createTreeWalker(result[i],NodeFilter.SHOW_ELEMENT);
          for(let el=walker.nextNode();el && budget-- > 0;el=walker.nextNode()) if(el.shadowRoot && result.length<32) result.push(el.shadowRoot);
        }
        return result;
      };
      const visible = el => el && el.isConnected && !el.disabled && !el.readOnly && !el.hidden && el.getClientRects().length>0 && getComputedStyle(el).visibility!=='hidden' && getComputedStyle(el).opacity!=='0' && !el.closest('[inert]');
      const passwords = () => roots().flatMap(r=>[...r.querySelectorAll('input[type="password"]')]).filter(visible).slice(0,16);
      const loginUsername = el => visible(el) && ['text','email','tel'].includes(el.type) && /(^|\s)username(\s|$)/i.test(el.autocomplete || '');
      const candidates = () => {
        const list=passwords();
        const names=roots().flatMap(r=>[...r.querySelectorAll('input')]).filter(el=>loginUsername(el) && !list.some(pw=>pw.form===el.form));
        return [...list,...names].slice(0,16);
      };
      const usable = pw => {
        if(!visible(pw) || (pw.type!=='password' && !loginUsername(pw))) return false;
        const form=pw.form;
        if(form) { try { const action=new URL(form.action || location.href,location.href); if(action.origin!==location.origin || !/^https?:$/.test(action.protocol)) return false; } catch(_){return false;} }
        return true;
      };
      const isCurrent = pw => !/(new-password|one-time-code)/i.test(pw.autocomplete || '');
      const refresh = () => {
        timer=null;
        const list=candidates();
        for(const [el] of hints)if(!el.isConnected)hints.delete(el);
        for(const [id,pw] of fields) if(!list.includes(pw)) fields.delete(id);
        const forms=list.filter(usable).map(pw=>{
          let id=ids.get(pw);if(!id){id=String(++serial);ids.set(pw,id);}fields.set(id,pw);
          if(pw.type==='password')prepareHints(pw, passwords());
          const user=pw.type==='password' ? username(pw) : null, focus=pw.getRootNode().activeElement || document.activeElement;
          const automatic=isCurrent(pw) && !dirty.has(pw) && (!user || !dirty.has(user)) && pw.value.length===0 && (!user || user.value.length===0);
          return {id,current:isCurrent(pw),passwordField:pw.type==='password',automatic,focused:focus===pw || focus===user};
        });
        try { window.webkit.messageHandlers.browserPasswords.postMessage({doc,forms}); } catch(_){}
      };
      const changed = () => {if(!timer)timer=setTimeout(refresh,150);};
      const username = pw => {
        const root=pw.form || pw.getRootNode();
        const inputs=[...root.querySelectorAll('input')].filter(el=>el!==pw && el.form===pw.form && visible(el) && ['text','email','tel'].includes(el.type) && !/(one-time-code|cc-)/i.test(el.autocomplete || ''));
        const explicit=inputs.filter(el=>el.autocomplete==='username');
        if(explicit.length===1)return explicit[0];
        const named=inputs.filter(el=>/^(username|email|login|user|account|login_email)$/i.test(el.name || el.id || ''));
        if(named.length===1)return named[0];
        const before=inputs.filter(el=>el.compareDocumentPosition(pw)&Node.DOCUMENT_POSITION_FOLLOWING);
        return before.length===1 ? before[0] : null;
      };
      const hint = (el,value) => {
        if(!el) return;
        const old=el.getAttribute('autocomplete');
        if(old && !['off','on'].includes(old.toLowerCase())) return;
        if(!hints.has(el)) hints.set(el,{old,value});
        el.setAttribute('autocomplete',value);
      };
      const prepareHints = (pw,list) => {
        if(!hintsEnabled || !isCurrent(pw) || list.filter(other=>other.form===pw.form).length!==1) return;
        hint(pw,'current-password'); hint(username(pw),'username');
      };
      const setHints = enabled => {
        hintsEnabled=!!enabled;
        if(!enabled) {
          for(const [el,change] of hints) if(el.isConnected && el.getAttribute('autocomplete')===change.value) {
            if(change.old===null) el.removeAttribute('autocomplete'); else el.setAttribute('autocomplete',change.old);
          }
          hints.clear();
        }
        changed();
      };
      const set = (el,value) => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el,value);
        el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true}));
      };
      // Capture only at an actual user submission gesture, never on typing.
      // Do not hook form prototypes, prevent submission, or send page URLs.
      let gestureAt=-Infinity;
      const offer = form => {
        if(!saveEnabled || window!==window.top || document.visibilityState!=='visible' || !form || form.matches(':invalid'))return;
        const list=passwords().filter(pw=>pw.form===form && usable(pw));
        if(!list.length || list.length>3)return;
        const fresh=list.filter(pw=>/(^|\s)new-password(\s|$)/i.test(pw.autocomplete || ''));
        let pw;
        if(fresh.length) {
          if(fresh.length>2 || fresh.some(el=>el.value!==fresh[0].value))return;
          pw=fresh[0];
        } else {
          if(list.length!==1 || !isCurrent(list[0]))return;
          pw=list[0];
        }
        const user=username(pw), value=pw.value;
        if(!value || value.length>16384 || (user && user.value.length>4096))return;
        refresh();
        try {window.webkit.messageHandlers.browserPasswords.postMessage({kind:'save',doc,form:ids.get(pw),
          username:user ? user.value : '',password:value,passwordChange:fresh.length>0});}catch(_){}
      };
      document.addEventListener('keydown',e=>{if(e.isTrusted && e.key==='Enter')gestureAt=performance.now();},true);
      document.addEventListener('click',e=>{
        if(!e.isTrusted)return;
        const button=e.composedPath().find(el=>el instanceof HTMLButtonElement || el instanceof HTMLInputElement);
        if(button && button.form && ((button instanceof HTMLButtonElement && button.type==='submit') ||
            (button instanceof HTMLInputElement && ['submit','image'].includes(button.type)))) {
          gestureAt=performance.now(); offer(button.form);
        }
      },true);
      document.addEventListener('submit',e=>{
        if(e.isTrusted && performance.now()-gestureAt<2000)offer(e.target);
      },true);
      globalThis.__personalBrowserPasswords={setHints,setSaveOffers:enabled=>{saveEnabled=!!enabled;},command:command=>{
        if(command.action==='refresh'){refresh();return {ok:true};}
        if(document.visibilityState!=='visible' || command.doc!==doc)return {ok:false};
        const pw=fields.get(command.form); if(!pw || !usable(pw))return {ok:false};
        const passwordField=pw.type==='password';
        const user=passwordField ? username(pw) : null;
        if(command.action==='focus') {
          if(!isCurrent(pw))return {ok:false};
          if(passwordField)prepareHints(pw,passwords());
          const field=user || pw;
          field.focus(); return {ok:field.getRootNode().activeElement===field || document.activeElement===field};
        }
        if(command.action==='fill') {
          if(!isCurrent(pw) || (passwordField && typeof command.password!=='string') || typeof command.username!=='string')return {ok:false};
          if(command.automatic && (window!==window.top || dirty.has(pw) || (user && dirty.has(user)) || pw.value.length!==0 || (user && user.value.length!==0) || candidates().filter(usable).length!==1))return {ok:false};
          if(!passwordField) {if(command.password!==undefined)return {ok:false};set(pw,command.username);return {ok:pw.value===command.username};}
          if(user)set(user,command.username);
          // Recheck after site input handlers: they may navigate/replace fields.
          if(!usable(pw) || document !== pw.ownerDocument || (command.automatic && (dirty.has(pw) || pw.value.length!==0)))return {ok:false};
          set(pw,command.password);return {ok:pw.value===command.password};
        }
        if(command.action==='capture' && passwordField) {
          // Only a native user action calls this branch. Observers never read
          // values or send credentials through the unsolicited message channel.
          return {ok:true,username:user ? user.value : '',password:pw.value};
        }
        return {ok:false};
      }};
      new MutationObserver(changed).observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['type','autocomplete','disabled','readonly','hidden','style','class']});
      for(const event of ['input','change']) document.addEventListener(event,e=>{if(e.isTrusted && e.target instanceof HTMLInputElement)dirty.add(e.target);changed();},true);
      document.addEventListener('focusin',changed,true); document.addEventListener('focusout',changed,true); window.addEventListener('pageshow',refresh);
      document.addEventListener('DOMContentLoaded',refresh); setInterval(refresh,2000); refresh();
    })();
    """#
}
