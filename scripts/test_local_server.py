#!/usr/bin/env python3
"""Loopback-only deterministic WebKit UI fixtures; never connects to user devices."""
import argparse
import base64
import html
import io
import math
import struct
import re
import ssl
import threading
import subprocess
import wave
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cert', required=True)
    parser.add_argument('--key', required=True)
    parser.add_argument('--simulator-id')
    args = parser.parse_args()
    audio = io.BytesIO()
    with wave.open(audio, 'wb') as stream:
        stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(8000)
        # Audible PCM makes the fixture exercise a real playback audio session.
        second = b''.join(struct.pack('<h', round(2000 * math.sin(2 * math.pi * 440 * i / 8000))) for i in range(8000))
        # Multi-tab UI navigation can exceed a short clip's duration. Keep the
        # fixture well beyond the scenario so end-of-file/loop seeks do not
        # masquerade as concurrent-playback interruption.
        stream.writeframes(second * 600)
    audio = audio.getvalue()

    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def do_GET(self):
            external_cases = {
                '/test-open-cold': 'mybrowser://open?url=http%3A%2F%2F127.0.0.1%3A18765%2Fexternal-cold%3Fa%3D1%26b%3D2',
                '/test-open-warm': 'mybrowser://open?url=http%3A%2F%2F127.0.0.1%3A18765%2Fexternal-warm',
                '/test-open-invalid': 'mybrowser://open?url=javascript%3Aalert(1)',
            }
            if self.path in external_cases and args.simulator_id:
                # Exercise actual OS delivery, including a terminated app. No
                # URL/command supplied by a request is executed by this helper.
                # Reply before waiting for launch: simctl can wait for the OS
                # confirmation that the UI test must tap after this response.
                child = subprocess.Popen(['xcrun', 'simctl', 'openurl', args.simulator_id, external_cases[self.path]],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                threading.Thread(target=child.wait, daemon=True).start()
                self.send_response(204)
                self.send_header('Content-Length', '0'); self.end_headers(); return
            if self.path in ['/wide.mp4', '/tall.mp4']:
                data = (Path(__file__).resolve().parents[1] / 'UITests/Fixtures' / self.path[1:]).read_bytes()
                mime = 'video/mp4'
            elif self.path == '/video-orientation-fixture':
                data = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>Video orientation fixture</title><style>video{width:100%;height:200px}button{font-size:16px;padding:10px}</style>
                <video id="wide" src="/wide.mp4" playsinline preload="auto"></video>
                <video id="tall" src="/tall.mp4" playsinline preload="auto" hidden></video>
                <button onclick="wide.play()">Play wide</button><button onclick="wide.pause()">Pause wide</button>
                <button onclick="wide.pause();wide.hidden=true;tall.hidden=false">Show tall</button>
                <button onclick="tall.play();tall.webkitEnterFullscreen()">Tall fullscreen</button>
                <button onclick="check()">Check video state</button><p id="result">Video ready</p>
                <script>
                let count=0,start=0,advanced=false;
                for(const v of [wide,tall]){
                  v.addEventListener('webkitbeginfullscreen',()=>{count++;start=v.currentTime});
                  v.addEventListener('webkitendfullscreen',()=>{advanced=v.currentTime>start+0.5});
                }
                function check(){result.textContent='Fullscreen count '+count+'; continued '+advanced+'; wide paused '+wide.paused}
                </script>'''
                mime = 'text/html; charset=utf-8'
            elif self.path == '/audio.wav':
                data, mime = audio, 'audio/wav'
            elif self.path in ['/concurrent-audio-a', '/concurrent-audio-b', '/volume-fixture']:
                title = 'Volume fixture' if self.path == '/volume-fixture' else 'Concurrent A' if self.path.endswith('-a') else 'Concurrent B'
                # A different loopback port guarantees a second origin without
                # localhost DNS/IPv6 differences. iOS may defer preload: start
                # this player explicitly before testing its CORS-mode reload.
                extra_player = '<audio id="third" aria-label="No CORS" src="http://127.0.0.1:18767/audio.wav" preload="auto"></audio><button onclick="document.getElementById(\'third\').play()">Play third</button>' if self.path == '/volume-fixture' else ''
                data = ('''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>''' + title + '''</title><h1>''' + title + '''</h1>
                <audio id="first" src="/audio.wav" loop preload="auto"></audio>
                <audio id="second" src="/audio.wav" loop preload="auto"></audio>
                <button onclick="document.getElementById('first').play()">Play first</button><button onclick="document.getElementById('second').play()">Play second</button>
                <button onclick="document.getElementById('first').pause()">Pause first</button><button onclick="document.getElementById('first').pause();document.getElementById('second').pause()">Pause both</button>
                <p id="progress">0,0,false,false</p>
                <script>
                const players=[document.getElementById('first'),document.getElementById('second')];
                const total=[0,0],previous=[0,0];
                function sample(){players.forEach((p,i)=>{
                  const delta=p.currentTime-previous[i];
                  total[i]+=delta>=0?delta:Math.max(0,p.duration-previous[i]+p.currentTime);
                  previous[i]=p.currentTime;
                });document.getElementById('progress').textContent=total.map(t=>t.toFixed(3)).join(',')+','+players.map(p=>!p.paused&&!p.ended).join(',');}
                setInterval(sample,250);
                </script>''' + extra_player).encode('utf-8')
                mime = 'text/html; charset=utf-8'
            elif self.path == '/password-vault-fixture':
                data = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>Password fixture</title>
                <style>body{font:16px -apple-system;margin:8px}h1{font-size:20px}input{font-size:16px;box-sizing:border-box;max-width:100%;width:100%;display:block;margin:6px 0}button{font-size:14px;margin:3px 2px}</style><h1>Password fixture</h1>
                <form onsubmit="event.preventDefault();window.fixtureSubmitted=true;document.getElementById('status').textContent='Submitted'">
                <input aria-label="Fixture username" id="user" name="username" autocapitalize="none" autocorrect="off" spellcheck="false">
                <input aria-label="Fixture password" id="pw" type="password">
                <button type="button" onclick="document.getElementById('status').textContent=document.getElementById('user').value==='fixture-user' &amp;&amp; document.getElementById('pw').value==='fixture-secret'?'Fields filled; not submitted':'Fields empty'">Check password fill</button>
                <button type="button" onclick="document.getElementById('user').value='';document.getElementById('pw').value='';window.fixtureSubmitted=false;document.getElementById('status').textContent='Fields empty'">Reset login form</button>
                <button type="button" onclick="this.form.innerHTML='&lt;input aria-label=UsernameOnly id=user autocomplete=username&gt;';document.getElementById('status').textContent='Username step empty'">Username-only step</button>
                </form><p id="status">Not submitted</p><p id="system-status"></p>
                <button onclick="showCredentialForm(false)">Login form</button>
                <button onclick="showCredentialForm(true)">Registration form</button>
                <button onclick="showCredentialForm(true)">Change password form</button>
                <script>
                function showCredentialForm(fresh) {
                  window.fixtureSubmitted=false;
                  document.querySelector('form').innerHTML='<input aria-label="Fixture username" id="user" name="username" autocomplete="username">'+
                    (fresh?'<input aria-label="New password" id="new" type="password" autocomplete="new-password"><input aria-label="Confirm password" id="confirm" type="password" autocomplete="new-password">':'<input aria-label="Fixture password" id="pw" type="password" autocomplete="current-password">')+
                    '<button>Submit credentials</button>';
                  document.getElementById('status').textContent='Fields empty';
                }
                document.addEventListener('focusin',e=>{
                  if(['user','pw'].includes(e.target.id) && document.getElementById('user').autocomplete==='username' && document.getElementById('pw')?.autocomplete==='current-password')document.getElementById('system-status').textContent='System field focused; hints ready';
                });
                setInterval(()=>{
                  const user=document.getElementById('user').value,pw=document.getElementById('pw')?.value;
                  if(window.fixtureSubmitted)document.getElementById('status').textContent='Submitted';
                  else if(user==='fixture-user' && pw==='fixture-secret')document.getElementById('status').textContent='Fields filled; not submitted';
                  else if(user==='new-account' && pw==='registered-fixture')document.getElementById('status').textContent='New account filled; not submitted';
                  else if(user==='new-account' && pw==='updated-fixture')document.getElementById('status').textContent='Updated account filled; not submitted';
                  else if(!document.getElementById('pw') && user==='fixture-user')document.getElementById('status').textContent='Username step filled; not submitted';
                  else if(user==='my-edit')document.getElementById('status').textContent='User edit retained';
                },200);
                </script>'''
                mime = 'text/html; charset=utf-8'
            elif self.path == '/locked-viewport':
                data = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>Locked viewport</title><style>html,body{overflow:hidden;height:100%;margin:0}.cover{position:fixed;inset:0;touch-action:none;background:#ddd}</style>
                <div class="cover" role="dialog" aria-modal="true"><h1>Locked viewport</h1><p>Document scrolling is blocked.</p></div>
                <script>document.addEventListener('touchmove',e=>e.preventDefault(),{passive:false});</script>'''
                mime = 'text/html; charset=utf-8'
            elif self.path == '/app-promotion-fixture':
                data = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>App promotion fixture</title><style>body.rpl-scroll-lock{overflow:hidden}main{min-height:900px}dialog{max-width:280px}</style>
                <main inert><h1>Promotion content</h1><p id="choice"></p><p id="result"></p>
                <button onclick="document.getElementById('result').textContent='Underlying action worked'">Underlying action</button>
                <button onclick="document.getElementById('login').showModal()">Show login</button>
                <button onclick="check()">Check compatibility</button></main>
                <dialog id="app-upsell-blocking-bottom-sheet-direct"><p>Use the Reddit app</p><a href="https://reddit.app.link/test">Open app</a>
                <button onclick="this.closest('dialog').close();document.getElementById('choice').textContent='Browser choice used'">Continue in browser</button></dialog>
                <div id="shadow-host"></div><div class="smartbanner"><a href="https://apps.apple.com/app/id123">Get app</a></div>
                <dialog id="login"><p>Login remains</p><button onclick="this.closest('dialog').close()">Close login</button></dialog>
                <script>
                document.body.className='rpl-scroll-lock';
                document.getElementById('shadow-host').attachShadow({mode:'open'}).innerHTML='<xpromo-app-selector><a href="reddit://test">Open app</a></xpromo-app-selector>';
                document.getElementById('app-upsell-blocking-bottom-sheet-direct').showModal();
                function check(){const n=document.getElementById('shadow-host').shadowRoot.querySelector('xpromo-app-selector');
                  const ok=!document.querySelector('main').inert && getComputedStyle(document.body).overflowY!=='hidden' &&
                  !document.getElementById('app-upsell-blocking-bottom-sheet-direct').open && getComputedStyle(n).display==='none' && getComputedStyle(document.querySelector('.smartbanner')).display==='none';
                  document.getElementById('result').textContent=ok?'Promotion removed; content usable':'Still blocked';}
                </script>'''
                mime = 'text/html; charset=utf-8'
            elif self.path == '/selection-fixture':
                data = '''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>Selection fixture</title><p id="sample">日本語 C++ &amp; # %2B</p>
                <button onclick="const r=document.createRange();r.selectNodeContents(document.getElementById('sample'));const s=window.getSelection();s.removeAllRanges();s.addRange(r);">Select sample text</button>'''.encode('utf-8')
                mime = 'text/html; charset=utf-8'
            elif self.path == '/navigation-fixture':
                data = b'<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><a href="/linked">Browser link</a><form method="post" action="/submitted"><input type="hidden" name="value" value="one"><button>Submit POST</button></form>'
                mime = 'text/html; charset=utf-8'
            elif self.path == '/layout-fixture':
                data = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
                <body style="background:white;color:black"><h1>Visible layout fixture</h1>
                <input aria-label="Layout username" autocomplete="username" style="font-size:16px">
                <button onclick="document.activeElement.blur();document.getElementById('result').textContent='Visible page responded'">Check visible page</button>
                <p id="result">Ready</p></body>'''
                mime = 'text/html; charset=utf-8'
            elif self.path == '/scroll-fixture':
                data = b'<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Scroll fixture</title><h1>Scroll fixture</h1><div style="height:1100px;background:linear-gradient(white,lightblue)">Scroll down</div><p>Bottom</p>'
                mime = 'text/html; charset=utf-8'
            elif self.path in ['/ads/banners/ad.png', '/allowed/visible.png']:
                data = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
                mime = 'image/png'
            elif self.path == '/blocking-fixture':
                data = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>Blocking fixture</title><h1>Blocking fixture ready</h1>
                <div class="adsbygoogle-noablate">Controlled advertisement</div>
                <button id="check" disabled onclick="document.getElementById('state').textContent=(window.testControlLoaded && !window.testAdLoaded && getComputedStyle(document.querySelector('.adsbygoogle-noablate')).display==='none')?'Blocked and hidden':'Not blocked';">Check filtering</button>
                <img src="http://localhost:18765/allowed/visible.png" onload="window.testControlLoaded=true;document.getElementById('check').disabled=false;">
                <img src="http://localhost:18765/ads/banners/ad.png" onload="window.testAdLoaded=true;">
                <p id="state"></p>'''
                mime = 'text/html; charset=utf-8'
            elif self.path == '/tab-child':
                data = b'<meta name="viewport" content="width=device-width,initial-scale=1"><title>Tab child</title><h1>Tab child ready</h1>'
                mime = 'text/html; charset=utf-8'
            elif self.path == '/media':
                data = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Audio fixture</title>
                <audio id="audio" src="/audio.wav" preload="auto"></audio>
                <button onclick="document.getElementById('audio').play()">Play test audio</button>
                <button onclick="sampleAudio()">Check audio state</button>
                <script>
                let samples = 0;
                function sampleAudio() {
                  const a = document.getElementById('audio');
                  document.getElementById('status').textContent = 'Sample ' + (++samples) + ':' +
                    (a.paused ? 'Paused' : 'Playing') + ':' + a.currentTime.toFixed(3) +
                    ':ready=' + a.readyState + ':error=' + (a.error ? a.error.code : 'none') + ':wall=' + Date.now();
                }
                </script>
                <p id="status"></p>'''
                mime = 'text/html; charset=utf-8'
            else:
                path = html.escape(self.path)
                data = ('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Local fixture</title><h1>Local connection ' + path + '</h1>').encode()
                mime = 'text/html; charset=utf-8'
            total = len(data); code = 200; content_range = None
            requested_range = self.headers.get('Range', '')
            if self.path in ['/audio.wav', '/wide.mp4', '/tall.mp4'] and (match := re.fullmatch(r'bytes=(\d+)-(\d*)', requested_range)):
                start = int(match[1]); end = min(total - 1, int(match[2]) if match[2] else total - 1)
                if 0 <= start <= end < total:
                    data = data[start:end + 1]; code = 206; content_range = f'bytes {start}-{end}/{total}'
            self.send_response(code); self.send_header('Content-Type', mime)
            if content_range: self.send_header('Content-Range', content_range)
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(len(data))); self.send_header('Cache-Control', 'no-store')
            self.end_headers(); self.wfile.write(data)

        def do_POST(self):
            body = self.rfile.read(min(4096, int(self.headers.get('Content-Length', '0')))).decode('utf-8')
            data = ('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><p>POST kept: ' + html.escape(body) + '</p>').encode()
            self.send_response(200); self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)

        def log_message(self, *args):
            pass

    servers = [ThreadingHTTPServer(('127.0.0.1', 18765), Handler), ThreadingHTTPServer(('127.0.0.1', 18766), Handler),
               ThreadingHTTPServer(('127.0.0.1', 18767), Handler)]
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(args.cert, args.key)
    servers[1].socket = context.wrap_socket(servers[1].socket, server_side=True)
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    # A subprocess (simctl) may wake signal.pause through SIGCHLD on macOS.
    # Keep the fixture alive until the CI cleanup terminates this process.
    threading.Event().wait()


if __name__ == '__main__':
    main()
