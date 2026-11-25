// Policy checks in Chromium. A fake AudioSession exposes type ownership only;
// actual WK fullscreen, OS inactivity and real media clocks run in native CI.
const {chromium} = require('playwright');
const fs = require('fs');
const assert = require('assert/strict');
const raw = (path, member) => fs.readFileSync(path, 'utf8').split(member)[1].split('#"""')[1].split('"""#')[0];
(async () => {
  const browser = await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
  try {
    const page = await browser.newPage();
    await page.addInitScript(() => {
      const session = new EventTarget(); session.type = window === window.top ? 'ambient' : 'auto';
      Object.defineProperty(navigator, 'audioSession', {value:session});
      window.messages = [];
      window.webkit = {messageHandlers:{browserAudioMixing:{postMessage:m=>messages.push(m)}, browserBackgroundAudio:{postMessage() {}}}};
    });
    await page.addInitScript(raw('App/AudioMixingController.swift', 'static let script =').replaceAll('__MIXING__','true'));
    await page.addInitScript(raw('App/BackgroundAudioScript.swift', 'static let source ='));
    await page.route('https://media.test/**', route=>route.fulfill({contentType:'text/html',body:'<audio id="player"></audio><video id="video"></video><iframe src="https://embedded.test/player"></iframe>'}));
    await page.route('https://embedded.test/**', route=>route.fulfill({contentType:'text/html',body:'<audio></audio><video id="video"></video>'}));
    await page.goto('https://media.test/');
    assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'ambient');
    const frame = page.frames().find(frame=>frame.url().startsWith('https://embedded.test/'));
    assert.ok(frame);
    assert.equal(await frame.evaluate(()=>navigator.audioSession.type), 'auto', 'Embedded documents must not be forced ambient');
    for (const mixing of [false, true, false]) {
      await page.evaluate(mixing=>{
        navigator.audioSession.type='ambient'; __personalBrowserSetAudioMixing(mixing);
      }, mixing);
      assert.equal(await page.evaluate(()=>navigator.audioSession.type), mixing ? 'ambient' : 'auto', 'Web mixing must follow the actual preference');
    }
    await page.evaluate(()=>__personalBrowserSetAudioMixing(true));
    await page.evaluate(()=>{
      // Background entry may remember an old ambient type. Return must still
      // use the current foreground policy instead of restoring that old type.
      navigator.audioSession.type='ambient';
      __personalBrowserBackgroundAudio.policy(true);
      __personalBrowserBackgroundAudio.policy(false);
    });
    assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'ambient');
    await page.evaluate(()=>{__personalBrowserBackgroundAudio.policy(true);navigator.audioSession.dispatchEvent(new Event('statechange'));});
    assert.equal(await page.evaluate(()=>navigator.audioSession.type),'playback','Foreground events must not undo the owned background transition');
    await frame.evaluate(()=>{navigator.audioSession.type='ambient';__personalBrowserSetAudioMixing(true);});
    assert.equal(await frame.evaluate(()=>navigator.audioSession.type),'ambient','Child script must defer policy writes to the native top-page relay');
    assert.equal(await page.evaluate(()=>navigator.audioSession.type),'playback','A child must not undo the top-owned background transition');
    await page.evaluate(()=>__personalBrowserBackgroundAudio.policy(false));
    for (const event of ['statechange', 'pageshow', 'visibilitychange']) {
      await page.evaluate(event=>{
        navigator.audioSession.type='ambient';
        (event==='statechange'?navigator.audioSession:event==='pageshow'?window:document).dispatchEvent(new Event(event));
      }, event);
      assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'ambient');
    }
    await page.evaluate(()=>{navigator.audioSession.state='active';navigator.audioSession.dispatchEvent(new Event('statechange'));});
    assert.ok(await page.evaluate(()=>messages.some(m=>m.active===true && m.type==='ambient')), 'Active top-level Web Audio must notify native preparation');
    await frame.evaluate(()=>{navigator.audioSession.state='active';navigator.audioSession.dispatchEvent(new Event('statechange'));});
    assert.equal(await frame.evaluate(()=>messages.some(m=>m.active===true)),false,'A child cannot claim top-page activity');

    // Actual PiP and hardware lock need an iPhone. Model both WebKit's PiP
    // property and the native aggregate/phase handoff, never call play/exit.
    await page.evaluate(()=>{
      window.playCalls=0;window.exitCalls=0;
      video.play=()=>{playCalls++;return Promise.resolve();};
      video.webkitExitFullscreen=()=>{exitCalls++;};
    });
    for(const mixing of [true,false]) {
      await page.evaluate(mixing=>{
        __personalBrowserSetAudioMixing(mixing,false,true);
        video.webkitPresentationMode='picture-in-picture';
        video.dispatchEvent(new Event('webkitpresentationmodechanged'));
      },mixing);
      assert.equal(await page.evaluate(()=>navigator.audioSession.type),'playback','PiP overrides ambient/auto before lock');
      await page.evaluate(mixing=>{
        __personalBrowserSetAudioMixing(mixing,true,false); // willResignActive
        video.webkitPresentationMode='inline'; // iOS may hide the PiP window for lock
        video.dispatchEvent(new Event('webkitpresentationmodechanged'));
        __personalBrowserSetAudioMixing(mixing,false,false);
        navigator.audioSession.dispatchEvent(new Event('statechange'));
        __personalBrowserBackgroundAudio.configure(false,false); // PiP does not need background recovery enabled
        __personalBrowserBackgroundAudio.policy(true);
        __personalBrowserBackgroundAudio.policy(false);
      },mixing);
      assert.equal(await page.evaluate(()=>navigator.audioSession.type),'playback','PiP lease survives inactive window loss and background-policy restoration');
      await page.evaluate(mixing=>__personalBrowserSetAudioMixing(mixing,false,true),mixing);
      assert.equal(await page.evaluate(()=>navigator.audioSession.type),mixing?'ambient':'auto','Return to inline restores the saved preference');
    }
    await frame.evaluate(()=>{
      video.webkitPresentationMode='picture-in-picture';video.dispatchEvent(new Event('webkitpresentationmodechanged'));
    });
    assert.equal(await page.evaluate(()=>navigator.audioSession.type),'auto','Child cannot directly change the top policy');
    await page.evaluate(()=>__personalBrowserSetAudioMixing(true,true,false));
    assert.equal(await page.evaluate(()=>navigator.audioSession.type),'playback','Native aggregate carries cross-origin PiP');
    await page.evaluate(()=>__personalBrowserSetAudioMixing(true,true,true));
    assert.equal(await page.evaluate(()=>navigator.audioSession.type),'playback','Returning while still PiP must not restore ambient');
    await page.evaluate(()=>__personalBrowserSetAudioMixing(true,false,true));
    assert.equal(await page.evaluate(()=>navigator.audioSession.type),'ambient');
    assert.deepEqual(await page.evaluate(()=>[playCalls,exitCalls,video.paused]),[0,0,true],'Session protection never resumes paused media or exits PiP');
    await page.evaluate(()=>{navigator.audioSession.type='play-and-record'; __personalBrowserSetAudioMixing(true); __personalBrowserBackgroundAudio.policy(true); __personalBrowserBackgroundAudio.policy(false);});
    assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'play-and-record', 'Capture must not be replaced');
    assert.equal(await page.evaluate(()=>player.paused), true, 'No policy event may start stopped media');
    await page.evaluate(()=>{player.muted=true;player.volume=0;__personalBrowserSetAudioMixing(true);});
    assert.deepEqual(await page.evaluate(()=>[player.muted,player.volume]), [true,0]);
    process.stdout.write('Playback policy passed: both settings, PiP/lock ownership and cross-origin aggregate, inline restore, capture, pause, mute; no play or exit calls.\n');
  } finally { await browser.close(); }
})().catch(error=>{process.stderr.write(String(error.stack)+'\n');process.exitCode=1;});
