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
    await page.route('https://media.test/**', route=>route.fulfill({contentType:'text/html',body:'<audio id="player"></audio><iframe src="https://embedded.test/player"></iframe>'}));
    await page.route('https://embedded.test/**', route=>route.fulfill({contentType:'text/html',body:'<audio></audio>'}));
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
    await page.evaluate(()=>{navigator.audioSession.type='play-and-record'; __personalBrowserSetAudioMixing(true); __personalBrowserBackgroundAudio.policy(true); __personalBrowserBackgroundAudio.policy(false);});
    assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'play-and-record', 'Capture must not be replaced');
    assert.equal(await page.evaluate(()=>player.paused), true, 'No policy event may start stopped media');
    await page.evaluate(()=>{player.muted=true;player.volume=0;__personalBrowserSetAudioMixing(true);});
    assert.deepEqual(await page.evaluate(()=>[player.muted,player.volume]), [true,0]);
    process.stdout.write('Playback policy passed: both settings, inactive return signals, background restore, capture, pause and mute.\n');
  } finally { await browser.close(); }
})().catch(error=>{process.stderr.write(String(error.stack)+'\n');process.exitCode=1;});
