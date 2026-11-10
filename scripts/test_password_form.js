// DOM regression checks in Chromium. Native WKWebView/Keychain have separate CI coverage.
const {chromium} = require('playwright');
const fs = require('fs');
const assert = require('assert/strict');
(async () => {
  const swift = fs.readFileSync('App/PasswordFormScript.swift', 'utf8');
  const script = swift.split('static let source = #"""')[1].split('"""#')[0];
  const browser = await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox'],headless:true});
  try {
    let errors = [];
    async function pageFor(inputs, action='') {
      const page = await browser.newPage();
      page.on('pageerror', e=>errors.push(e.message));
      await page.addInitScript(() => {window.messages=[];window.webkit={messageHandlers:{browserPasswords:{postMessage:m=>window.messages.push(m)}}};});
      await page.addInitScript(script);
      await page.route('https://example.test/**',route=>route.fulfill({contentType:'text/html',body:`<form action="${action}" onsubmit="event.preventDefault()">${inputs}<button>Send</button></form><input id="search" type="search">`}));
      await page.goto('https://example.test/login');
      return page;
    }
    const login='<input id="user" name="username" autocomplete="username"><input id="pw" type="password" autocomplete="current-password">';
    let page=await pageFor(login);
    await page.fill('#user','fixture-user'); await page.fill('#pw','fixture-password');
    assert.equal(await page.evaluate(()=>messages.filter(m=>m.kind==='save').length),0,'Typing must not transmit credentials');
    await page.click('button');
    assert.ok(await page.evaluate(()=>messages.some(m=>m.kind==='save' && m.username==='fixture-user' && m.password==='fixture-password')));
    await page.click('#search'); await page.waitForTimeout(200);
    assert.ok(await page.evaluate(()=>messages.filter(m=>m.forms).at(-1).forms.every(f=>!f.focused)),'Search focus must clear login candidates');
    await page.close();
    page=await pageFor(login);
    await page.fill('#pw','fixture-password');
    await page.evaluate(()=>document.querySelector('form').requestSubmit());
    assert.equal(await page.evaluate(()=>messages.filter(m=>m.kind==='save').length),0,'Programmatic submit without user gesture must not capture');
    await page.close();
    page=await pageFor(login+'<input id="new" type="password" autocomplete="new-password"><input id="confirm" type="password" autocomplete="new-password">');
    await page.fill('#user','fixture-user'); await page.fill('#pw','old-fixture');
    await page.fill('#new','new-fixture'); await page.fill('#confirm','different-fixture');
    await page.click('button');
    assert.equal(await page.evaluate(()=>messages.filter(m=>m.kind==='save').length),0,'Mismatched new passwords must not be offered');
    await page.fill('#confirm','new-fixture'); await page.click('button');
    assert.ok(await page.evaluate(()=>messages.some(m=>m.kind==='save' && m.password==='new-fixture' && m.passwordChange)));
    await page.evaluate(()=>globalThis.__personalBrowserPasswords.setSaveOffers(false));
    const count=await page.evaluate(()=>messages.filter(m=>m.kind==='save').length);
    await page.click('button'); assert.equal(await page.evaluate(()=>messages.filter(m=>m.kind==='save').length),count);
    await page.close();
    page=await pageFor(login,'https://other.test/');
    await page.fill('#pw','fixture-password'); await page.click('button');
    assert.equal(await page.evaluate(()=>messages.filter(m=>m.kind==='save').length),0,'Cross-origin form actions must not be captured');
    await page.close();
    assert.deepEqual(errors,[]);
    process.stdout.write('Password form DOM checks passed (typing isolation, trusted submit, focus, update confirmation, disabled, origin).\n');
  } finally {await browser.close();}
})().catch(error=>{process.stderr.write(String(error.stack)+'\n');process.exitCode=1;});
