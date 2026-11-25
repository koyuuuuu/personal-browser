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
      window.webkit={messageHandlers:{browserQuietFullscreen:{postMessage:value=>messages.push(value)}}};
      Object.defineProperty(HTMLVideoElement.prototype,'webkitSupportsFullscreen',{get(){return location.pathname==='/native';}});
      HTMLVideoElement.prototype.webkitEnterFullscreen=function(){events.push('video-enter');this.dispatchEvent(new Event('webkitbeginfullscreen'));};
      HTMLVideoElement.prototype.webkitExitFullscreen=function(){events.push('video-exit');this.dispatchEvent(new Event('webkitendfullscreen'));};
    });
    await context.addInitScript(script);
    const html=`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>#stage{width:200px;height:150px}#stage:fullscreen{color:rgb(1, 2, 3)}video{width:100px;height:60px}</style>
      <button id="go">Enter</button><button id="exit">Exit</button><div id="stage" style="width:200px"><video src="/video.mp4" loop playsinline></video><button id="inside">Exit inside</button></div>
      <script>const original=document.querySelector('video');window.original=original;window.stage=document.querySelector('#stage');window.count=0;document.addEventListener('fullscreenchange',()=>count++);go.onclick=()=>{original.play();stage.requestFullscreen().catch(e=>window.error=e.name);};exit.onclick=inside.onclick=()=>document.exitFullscreen();</script>`;
    await context.route('https://main.test/**',async route=>{
      if(route.request().url().endsWith('/video.mp4')) return route.fulfill({contentType:'video/mp4',body:fs.readFileSync('UITests/Fixtures/background-audio.mp4')});
      return route.fulfill({contentType:'text/html',body:route.request().url().endsWith('/embed')?'<iframe src="https://child.test/css" allow="fullscreen" style="width:250px;height:400px"></iframe>':html});
    });
    await context.route('https://child.test/**',route=>route.fulfill({contentType:route.request().url().endsWith('/video.mp4')?'video/mp4':'text/html',body:route.request().url().endsWith('/video.mp4')?fs.readFileSync('UITests/Fixtures/background-audio.mp4'):html}));
    const page=await context.newPage();
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
      original.webkitPresentationMode='picture-in-picture';
      original.dispatchEvent(new Event('webkitpresentationmodechanged'));
      dispatchEvent(new Event('pagehide'));
    });
    await page.evaluate(()=>document.exitFullscreen());
    assert.deepEqual(await page.evaluate(()=>({events,mode:original.webkitPresentationMode,full:document.fullscreenElement,same:original===document.querySelector('video')})),{events:['video-enter'],mode:'picture-in-picture',full:null,same:true},'PiP transition/pagehide cleans bookkeeping without calling native video exit');
    await page.reload();await page.click('#go');
    await page.waitForFunction(()=>document.fullscreenElement===stage);
    await page.evaluate(()=>{original.webkitPresentationMode='picture-in-picture';});
    await page.evaluate(()=>document.exitFullscreen());
    assert.deepEqual(await page.evaluate(()=>events),['video-enter'],'PiP getter also protects exit when mode notification is delayed');
    await page.goto('https://main.test/css');await page.click('#go');
    await page.waitForFunction(()=>original.currentTime>0.5 && document.fullscreenElement===stage);
    const beforePiP=await page.evaluate(()=>original.currentTime);
    await page.evaluate(()=>{original.webkitPresentationMode='picture-in-picture';original.dispatchEvent(new Event('webkitpresentationmodechanged'));});
    assert.deepEqual(await page.evaluate(()=>[document.fullscreenElement,stage.hasAttribute('popover'),original===document.querySelector('video'),events.length]),[null,false,true,0],'CSS fullscreen also releases only its wrapper when PiP begins');
    await page.waitForFunction(t=>original.currentTime>t+0.3,beforePiP);
    await page.goto('https://main.test/embed');
    const child=page.frameLocator('iframe');
    await child.locator('#go').click();
    await page.waitForFunction(()=>document.fullscreenElement===document.querySelector('iframe'));
    assert.deepEqual(await page.evaluate(()=>[document.querySelector('iframe').getBoundingClientRect().width,document.querySelector('iframe').getBoundingClientRect().height,nativeElementCalls]),[420,840,0]);
    await child.locator('#inside').click();
    await page.waitForFunction(()=>document.fullscreenElement===null);
    assert.equal(await child.locator('#stage').evaluate(e=>e.hasAttribute('popover')),false);
    console.log('Quiet fullscreen passed: original media/time retained, real top-layer sizing/style restoration, repeated entry/exit, cross-origin iframe chain, native-video routing; zero Element Fullscreen calls.');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
