import Foundation

enum PasswordFormScript {
    static let source = #"""
    (() => {
      if (globalThis.__personalBrowserPasswords) return;
      const doc = crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36)+Date.now();
      const ids = new WeakMap(), fields = new Map(); let serial = 0, timer = null;
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
      const usable = pw => {
        if(!visible(pw) || pw.type!=='password') return false;
        const form=pw.form;
        if(form) { try { const action=new URL(form.action || location.href,location.href); if(action.origin!==location.origin || !/^https?:$/.test(action.protocol)) return false; } catch(_){return false;} }
        return true;
      };
      const isCurrent = pw => !/(new-password|one-time-code)/i.test(pw.autocomplete || '');
      const refresh = () => {
        timer=null;
        const list=passwords();
        for(const [id,pw] of fields) if(!list.includes(pw)) fields.delete(id);
        const forms=list.filter(usable).map(pw=>{
          let id=ids.get(pw);if(!id){id=String(++serial);ids.set(pw,id);}fields.set(id,pw);
          return {id,current:isCurrent(pw)};
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
      const set = (el,value) => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el,value);
        el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true}));
      };
      globalThis.__personalBrowserPasswords={command:command=>{
        if(command.action==='refresh'){refresh();return {ok:true};}
        if(document.visibilityState!=='visible' || command.doc!==doc)return {ok:false};
        const pw=fields.get(command.form); if(!pw || !usable(pw))return {ok:false};
        const user=username(pw);
        if(command.action==='fill') {
          if(!isCurrent(pw) || typeof command.password!=='string' || typeof command.username!=='string')return {ok:false};
          if(user)set(user,command.username);
          // Recheck after site input handlers: they may navigate/replace fields.
          if(!usable(pw) || document !== pw.ownerDocument)return {ok:false};
          set(pw,command.password);return {ok:true};
        }
        if(command.action==='capture') {
          // Only a native user action calls this branch. Observers never read
          // values or send credentials through the unsolicited message channel.
          return {ok:true,username:user ? user.value : '',password:pw.value};
        }
        return {ok:false};
      }};
      new MutationObserver(changed).observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['type','autocomplete','disabled','readonly','hidden','style','class']});
      document.addEventListener('focusin',changed,true); window.addEventListener('pageshow',refresh);
      document.addEventListener('DOMContentLoaded',refresh); setInterval(refresh,2000); refresh();
    })();
    """#
}
