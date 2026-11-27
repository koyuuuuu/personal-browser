// Actual Chromium popover/layout/media checks; legacy iOS video calls are
// mocked here. Native player/speaker acceptance belongs to the user's device.
const {chromium} = require('playwright');
const fs = require('fs');
const assert = require('assert/strict');
const script=fs.readFileSync('App/QuietFullscreenController.swift','utf8').split('static let script =')[1].split('#"""')[1].split('"""#')[0];
(async()=>{
  const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({viewport:{width:420,height:840}});
    await context.addInitScript(()=>{
      window.nativeElementCalls=0;window.events=[];window.messages=[];
      Element.prototype.requestFullscreen=function(){nativeElementCalls++;throw Error('Native Element Fullscreen must never be used');};
      HTMLElement.prototype.webkitRequestFullscreen=Element.prototype.requestFullscreen;
      if(location.pathname==='/disabled') {
        for(const name of ['fullscreenEnabled','fullscreenElement','exitFullscreen','onfullscreenchange'])delete Document.prototype[name];
        delete Element.prototype.requestFullscreen;
        delete Element.prototype.onfullscreenchange;
      }
      window.webkit={messageHandlers:{browserQuietFullscreen:{postMessage:value=>messages.push(value)}}};
      Object.defineProperty(HTMLVideoElement.prototype,'webkitSupportsFullscreen',{get(){return ['/native','/native-fails'].includes(location.pathname);}});
      HTMLVideoElement.prototype.webkitEnterFullscreen=function(){events.push('video-enter');if(location.pathname==='/native-fails')throw Error('Native video unavailable');this.webkitPresentationMode='fullscreen';this.dispatchEvent(new Event('webkitbeginfullscreen'));};
      HTMLVideoElement.prototype.webkitExitFullscreen=function(){events.push('video-exit');this.webkitPresentationMode='inline';this.dispatchEvent(new Event('webkitendfullscreen'));};
    });
    await context.addInitScript(script);
    const html=`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>#stage{width:200px;height:150px}#stage:fullscreen{color:rgb(1, 2, 3)}video{width:100px;height:60px}</style>
      <button id="go">Enter</button><button id="exit">Exit</button><div id="stage" style="width:200px"><video src="/video.mp4" loop playsinline></video><button id="inside">Exit inside</button></div>
      <script>const original=document.querySelector('video');window.original=original;window.stage=document.querySelector('#stage');window.count=0;window.videoFrames=0;if(original.requestVideoFrameCallback)original.requestVideoFrameCallback(function tick(){videoFrames++;original.requestVideoFrameCallback(tick);});document.addEventListener('fullscreenchange',()=>count++);go.onclick=()=>{original.play();stage.requestFullscreen().catch(e=>window.error=e.name);};exit.onclick=inside.onclick=()=>document.exitFullscreen();</script>`;
    await context.route('https://main.test/**',async route=>{
      if(route.request().url().endsWith('/video.mp4')) return route.fulfill({contentType:'video/mp4',body:fs.readFileSync('UITests/Fixtures/background-audio.mp4')});
      const path=new URL(route.request().url()).pathname;
      const embeds={'/embed':'fullscreen','/embed-denied':"fullscreen 'none'",'/embed-ungranted':''};
      return route.fulfill({contentType:'text/html',headers:path==='/policy-denied'?{'Permissions-Policy':'fullscreen=()'}:{},body:path in embeds?`<iframe src="https://child.test/css" allow="${embeds[path]}" style="width:250px;height:400px"></iframe>`:html});
    });
    await context.route('https://child.test/**',route=>route.fulfill({contentType:route.request().url().endsWith('/video.mp4')?'video/mp4':'text/html',body:route.request().url().endsWith('/video.mp4')?fs.readFileSync('UITests/Fixtures/background-audio.mp4'):html}));
    const page=await context.newPage();
    for(const path of ['/disabled','/own-prototype','/native-fails']) {
      await page.goto('https://main.test'+path);
      await page.evaluate(()=>{
        window.handlerCount=0;window.elementCount=0;
        document.onfullscreenchange=()=>handlerCount++;
        stage.onfullscreenchange=()=>elementCount++;
        go.onclick=()=>{original.play();stage.webkitRequestFullscreen().catch(e=>window.error=e.name);};
      });
      assert.equal(await page.evaluate(()=>document.fullscreenEnabled && document.webkitFullscreenEnabled),true);
      await page.click('#go');await page.waitForFunction(()=>document.fullscreenElement===stage);
      assert.deepEqual(await page.evaluate(()=>[nativeElementCalls,stage.matches(':popover-open'),handlerCount,elementCount]),[0,true,1,1]);
      await page.click('#inside');
      await page.waitForFunction(()=>document.fullscreenElement===null && handlerCount===2 && elementCount===2);
    }
    await page.goto('https://main.test/policy-denied');
    await page.click('#go');
    await page.waitForFunction(()=>window.error==='NotAllowedError');
    assert.equal(await page.evaluate(()=>document.fullscreenEnabled),false);
    for(const path of ['/embed-denied','/embed-ungranted']) {
      await page.goto('https://main.test'+path);
      const denied=page.frameLocator('iframe');await denied.locator('#go').click();
      await denied.locator('#stage').evaluate(()=>new Promise(resolve=>setTimeout(resolve,100)));
      assert.deepEqual(await denied.locator('#stage').evaluate(()=>[document.fullscreenEnabled,document.fullscreenElement,window.error]),[false,null,'NotAllowedError']);
      assert.equal(await page.evaluate(()=>document.fullscreenElement),null);
    }
    await page.goto('https://main.test/css');
    for(let i=0;i<2;i++){
      await page.click('#go');
      await page.waitForFunction(()=>document.fullscreenElement===stage);
      assert.deepEqual(await page.evaluate(()=>({same:original===document.querySelector('video'),popover:stage.matches(':popover-open'),rect:[stage.getBoundingClientRect().width,stage.getBoundingClientRect().height],color:getComputedStyle(stage).color,native:nativeElementCalls})),{same:true,popover:true,rect:[420,840],color:'rgb(1, 2, 3)',native:0});
      await page.waitForFunction(()=>original.currentTime>0.7);
      const before=await page.evaluate(()=>original.currentTime);
      await page.click('#inside');
      assert.deepEqual(await page.evaluate(()=>({full:document.fullscreenElement,style:stage.getAttribute('style'),popover:stage.hasAttribute('popover'),count})),{full:null,style:'width:200px',popover:false,count:(i+1)*2});
      await page.waitForFunction(t=>original.currentTime>t+0.3,before);
    }
    await page.goto('https://main.test/native');
    await page.click('#go');await page.waitForFunction(()=>document.fullscreenElement===stage);
    assert.deepEqual(await page.evaluate(()=>events),['video-enter']);
    await page.evaluate(()=>document.exitFullscreen());
    assert.deepEqual(await page.evaluate(()=>({events,full:document.fullscreenElement,native:nativeElementCalls,same:original===document.querySelector('video')})),{events:['video-enter','video-exit'],full:null,native:0,same:true});
    await page.reload();
    await page.click('#go');await page.waitForFunction(()=>document.fullscreenElement===stage);
    await page.evaluate(()=>{
      original.dispatchEvent(new Event('webkitendfullscreen'));
      original.webkitPresentationMode='picture-in-picture';
      original.dispatchEvent(new Event('webkitpresentationmodechanged'));
      dispatchEvent(new Event('pagehide'));
    });
    await page.evaluate(()=>document.exitFullscreen());
    assert.deepEqual(await page.evaluate(()=>({events,mode:original.webkitPresentationMode,full:document.fullscreenElement===stage,count,same:original===document.querySelector('video')})),{events:['video-enter'],mode:'picture-in-picture',full:true,count:1,same:true},'PiP must not emit fullscreen-exit/rebuild or alter the source presentation');
    await page.evaluate(()=>{original.webkitPresentationMode='inline';document.dispatchEvent(new Event('visibilitychange'));});
    await page.waitForFunction(()=>document.fullscreenElement===null && count===2);
    await page.reload();await page.click('#go');
    await page.waitForFunction(()=>document.fullscreenElement===stage);
    await page.evaluate(()=>{original.webkitPresentationMode='picture-in-picture';});
    await page.evaluate(()=>document.exitFullscreen());
    assert.deepEqual(await page.evaluate(()=>events),['video-enter'],'PiP getter also protects exit when mode notification is delayed');
    await page.evaluate(()=>{original.webkitPresentationMode='fullscreen';original.dispatchEvent(new Event('webkitpresentationmodechanged'));});
    assert.equal(await page.evaluate(()=>document.fullscreenElement===stage && count===1),true,'Return from PiP to native fullscreen keeps the existing presentation');
    await page.evaluate(()=>document.exitFullscreen());
    await page.waitForFunction(()=>document.fullscreenElement===null && count===2);
    await page.goto('https://main.test/css');await page.click('#go');
    await page.waitForFunction(()=>original.currentTime>0.5 && document.fullscreenElement===stage);
    const beforePiP=await page.evaluate(()=>({time:original.currentTime,frames:videoFrames,style:stage.getAttribute('style')}));
    await page.evaluate(()=>{original.webkitPresentationMode='picture-in-picture';original.dispatchEvent(new Event('webkitpresentationmodechanged'));});
    assert.deepEqual(await page.evaluate(()=>[document.fullscreenElement===stage,stage.hasAttribute('popover'),original===document.querySelector('video'),events.length,count]),[true,true,true,0,1],'CSS/DOM viewport and fullscreen events must remain unchanged throughout PiP');
    await page.waitForFunction(before=>original.currentTime>before.time+0.3 && videoFrames>before.frames+2,beforePiP);
    assert.equal(await page.evaluate(()=>stage.getAttribute('style')),beforePiP.style);
    await page.evaluate(()=>{original.webkitPresentationMode='inline';original.dispatchEvent(new Event('leavepictureinpicture'));});
    await page.waitForFunction(()=>document.fullscreenElement===null && count===2);
    assert.equal(await page.evaluate(()=>stage.hasAttribute('popover')),false);
    await page.evaluate(()=>original.pause());
    assert.equal(await page.evaluate(()=>original.paused),true,'PiP cleanup must never resume a paused player');
    await page.goto('https://main.test/embed');
    const child=page.frameLocator('iframe');
    await child.locator('#go').click();
    await page.waitForFunction(()=>document.fullscreenElement===document.querySelector('iframe'));
    assert.deepEqual(await page.evaluate(()=>[document.querySelector('iframe').getBoundingClientRect().width,document.querySelector('iframe').getBoundingClientRect().height,nativeElementCalls]),[420,840,0]);
    await child.locator('#stage').evaluate(e=>{
      const v=e.querySelector('video');v.webkitPresentationMode='picture-in-picture';v.dispatchEvent(new Event('webkitpresentationmodechanged'));
    });
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    await page.evaluate(()=>document.exitFullscreen());
    assert.equal(await page.evaluate(()=>document.fullscreenElement===document.querySelector('iframe')),true,'Parent iframe must keep its viewport during child PiP');
    assert.equal(await child.locator('#stage').evaluate(e=>e.matches(':popover-open')),true);
    await child.locator('#stage').evaluate(e=>{
      const v=e.querySelector('video');v.webkitPresentationMode='inline';v.dispatchEvent(new Event('leavepictureinpicture'));
    });
    await page.waitForFunction(()=>document.fullscreenElement===null);
    assert.equal(await child.locator('#stage').evaluate(e=>e.hasAttribute('popover')),false);
    assert.match(fs.readFileSync('App/BrowserTab.swift','utf8'),/isElementFullscreenEnabled = false/);
    console.log('Quiet fullscreen passed: disabled-native API capabilities/events, own prefixed prototypes, native-video fallback, policy/iframe denial, decoded video and retained PiP/iframe handoff. Native video/PiP APIs are mocked; physical WebKit banner acceptance is not claimed.');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
