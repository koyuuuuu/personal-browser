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
      const session = new EventTarget(); session.type = 'ambient';
      Object.defineProperty(navigator, 'audioSession', {value:session});
      window.messages = [];
      window.webkit = {messageHandlers:{browserAudioMixing:{postMessage:m=>messages.push(m)}, browserBackgroundAudio:{postMessage() {}}}};
    });
    await page.addInitScript(raw('App/AudioMixingController.swift', 'static let script ='));
    await page.addInitScript(raw('App/BackgroundAudioScript.swift', 'static let source ='));
    await page.route('https://media.test/**', route=>route.fulfill({contentType:'text/html',body:'<audio id="player"></audio><iframe src="https://embedded.test/player"></iframe>'}));
    await page.route('https://embedded.test/**', route=>route.fulfill({contentType:'text/html',body:'<audio></audio>'}));
    await page.goto('https://media.test/');
    assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'playback');
    const frame = page.frames().find(frame=>frame.url().startsWith('https://embedded.test/'));
    assert.ok(frame);
    assert.equal(await frame.evaluate(()=>navigator.audioSession.type), 'playback', 'The real player document needs playback too');
    for (const mixing of [false, true, false]) {
      await page.evaluate(mixing=>{
        navigator.audioSession.type='ambient'; __personalBrowserSetAudioMixing(mixing);
      }, mixing);
      assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'playback', 'Both toggle values ignore Silent');
    }
    await page.evaluate(()=>{
      // Background entry may remember an old ambient type. Return must still
      // use the current foreground policy instead of restoring that old type.
      navigator.audioSession.type='ambient';
      __personalBrowserBackgroundAudio.policy(true);
      __personalBrowserBackgroundAudio.policy(false);
    });
    assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'playback');
    for (const event of ['statechange', 'pageshow', 'visibilitychange']) {
      await page.evaluate(event=>{
        navigator.audioSession.type='ambient';
        (event==='statechange'?navigator.audioSession:event==='pageshow'?window:document).dispatchEvent(new Event(event));
      }, event);
      assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'playback');
    }
    await page.evaluate(()=>{navigator.audioSession.type='play-and-record'; __personalBrowserSetAudioMixing(true); __personalBrowserBackgroundAudio.policy(true); __personalBrowserBackgroundAudio.policy(false);});
    assert.equal(await page.evaluate(()=>navigator.audioSession.type), 'play-and-record', 'Capture must not be replaced');
    assert.equal(await page.evaluate(()=>player.paused), true, 'No policy event may start stopped media');
    await page.evaluate(()=>{player.muted=true;player.volume=0;__personalBrowserSetAudioMixing(true);});
    assert.deepEqual(await page.evaluate(()=>[player.muted,player.volume]), [true,0]);
    process.stdout.write('Playback policy passed: both settings, inactive return signals, background restore, capture, pause and mute.\n');
  } finally { await browser.close(); }
})().catch(error=>{process.stderr.write(String(error.stack)+'\n');process.exitCode=1;});
