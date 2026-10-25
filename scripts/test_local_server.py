#!/usr/bin/env python3
"""Loopback-only deterministic WebKit UI fixtures; never connects to user devices."""
import argparse
import html
import io
import math
import struct
import signal
import re
import ssl
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cert', required=True)
    parser.add_argument('--key', required=True)
    args = parser.parse_args()
    audio = io.BytesIO()
    with wave.open(audio, 'wb') as stream:
        stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(8000)
        # Audible PCM makes the fixture exercise a real playback audio session.
        second = b''.join(struct.pack('<h', round(2000 * math.sin(2 * math.pi * 440 * i / 8000))) for i in range(8000))
        stream.writeframes(second * 45)
    audio = audio.getvalue()

    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def do_GET(self):
            if self.path == '/audio.wav':
                data, mime = audio, 'audio/wav'
            elif self.path == '/navigation-fixture':
                data = b'<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><a href="/linked">Browser link</a><form method="post" action="/submitted"><input type="hidden" name="value" value="one"><button>Submit POST</button></form>'
                mime = 'text/html; charset=utf-8'
            elif self.path == '/scroll-fixture':
                data = b'<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Scroll fixture</title><h1>Scroll fixture</h1><div style="height:1100px;background:linear-gradient(white,lightblue)">Scroll down</div><p>Bottom</p>'
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
            if self.path == '/audio.wav' and (match := re.fullmatch(r'bytes=(\d+)-(\d*)', requested_range)):
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

    servers = [ThreadingHTTPServer(('127.0.0.1', 18765), Handler), ThreadingHTTPServer(('127.0.0.1', 18766), Handler)]
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(args.cert, args.key)
    servers[1].socket = context.wrap_socket(servers[1].socket, server_side=True)
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    signal.pause()


if __name__ == '__main__':
    main()
