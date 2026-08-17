#!/usr/bin/env python3
"""Kokoro PDF reader daemon — warm neural TTS with transport controls.

Loads the Kokoro model once, holds one document as an ordered list of
sentences, and plays from a movable cursor so you get play / pause / skip while
you read along. Control is HTTP on 127.0.0.1 (loopback only), which also serves
a small control bar at `/`. 100% offline.

  GET  /          control bar (buttons + current sentence)
  GET  /status    {playing, index, total, sentence, voice, speed}
  POST /load      body: "<voice>\\t<speed>\\t<s1>\\x1f<s2>\\x1f..."  (resets, plays)
  POST /play /pause /toggle /next /prev /stop
  POST /speed?v=1.2

Env: VOICE_READER_PORT (8477), VOICE_KOKORO_VOICE, VOICE_KOKORO_SPEED.
"""
import http.server
import json
import os
import threading
import urllib.parse

import numpy as np
import sounddevice as sd
from kokoro_onnx import Kokoro

K = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("VOICE_READER_PORT", "8477"))
DEF_VOICE = os.environ.get("VOICE_KOKORO_VOICE", "af_heart")
DEF_SPEED = float(os.environ.get("VOICE_KOKORO_SPEED", "1.0"))

kok = Kokoro(os.path.join(K, "kokoro-v1.0.onnx"), os.path.join(K, "voices-v1.0.bin"))


class Player:
    """Playback state + the thread that renders it.

    Every command mutates state under `lock` and bumps `gen`, a generation
    counter. The player snapshots gen before the slow synth+play of a sentence
    and re-checks it before committing the cursor advance, so a pause/seek/load
    that lands mid-sentence cleanly wins instead of racing the advance.
    """

    def __init__(self):
        self.lock = threading.Lock()
        self.wake = threading.Event()
        self.sentences = []
        self.cursor = 0
        self.paused = True
        self.voice = DEF_VOICE
        self.speed = DEF_SPEED
        self.gen = 0
        self._stream = None
        self._sr = None
        threading.Thread(target=self._run, daemon=True).start()

    # ---- commands (HTTP threads) ----
    def load(self, sentences, voice, speed):
        with self.lock:
            self.sentences = sentences
            self.cursor = 0
            if voice:
                self.voice = voice
            if speed:
                self.speed = speed
            self.paused = not sentences
            self.gen += 1
        self.wake.set()

    def _flag(self, **kw):
        with self.lock:
            for k, v in kw.items():
                setattr(self, k, v)
            self.gen += 1
        self.wake.set()

    # play/pause/toggle change only whether we're speaking, not what sentence is
    # the synth target, so they do NOT bump gen. The player observes `paused`
    # directly. (Bumping gen here would suppress the auto-advance of a sentence
    # that finished exactly as pause landed, replaying it on resume.)
    def play(self):
        with self.lock:
            self.paused = False
        self.wake.set()

    def pause(self):
        with self.lock:
            self.paused = True
        self.wake.set()

    def toggle(self):
        with self.lock:
            self.paused = not self.paused
        self.wake.set()

    def stop(self):
        self._flag(paused=True, cursor=0)

    def seek(self, delta):
        with self.lock:
            if self.sentences:
                self.cursor = max(0, min(len(self.sentences) - 1, self.cursor + delta))
            self.gen += 1
        self.wake.set()

    def set_speed(self, v):
        # bump gen so the current sentence restarts at the new speed; clamp so a
        # raw POST that bypasses the UI can't pass 0 (undefined synth behavior).
        self._flag(speed=max(0.5, min(2.0, v)))

    def status(self):
        with self.lock:
            n = len(self.sentences)
            i = min(self.cursor, n - 1) if n else 0   # cursor==n at end-of-doc; report last
            cur = self.sentences[i] if n else ""
            return {
                "playing": not self.paused,
                "index": i,
                "total": n,
                "sentence": cur,
                "voice": self.voice,
                "speed": self.speed,
            }

    # ---- audio device (persistent stream, reused across sentences) ----
    def _out(self, sr):
        if self._stream is None or self._sr != sr:
            self._drop()
            self._stream = sd.OutputStream(
                samplerate=sr, channels=1, dtype="float32", latency="high"
            )
            self._stream.start()
            self._sr = sr
            self._stream.write(np.zeros(int(sr * 0.15), dtype="float32"))  # absorb cold-start ramp
        return self._stream

    def _drop(self):
        if self._stream is not None:
            try:
                self._stream.abort()
                self._stream.close()
            except Exception:
                pass
        self._stream = None
        self._sr = None

    # ---- player thread ----
    def _run(self):
        while True:
            try:
                self._tick()
            except Exception:
                # A device error (output unplugged, sample rate refused) must not
                # kill the only player thread and leave the daemon silently deaf.
                # Drop the stream and retry on the next tick, throttled so a
                # persistently-gone device doesn't hot-loop.
                self._drop()
                self.wake.wait(timeout=0.5)

    def _tick(self):
        with self.lock:
            if self.paused or not (0 <= self.cursor < len(self.sentences)):
                snap = None
            else:
                snap = (self.sentences[self.cursor], self.cursor, self.gen,
                        self.voice, self.speed)
        if snap is None:
            # 0.5s poll is a lost-wakeup backstop: even if a command's wake.set
            # races our clear, we re-evaluate within half a second.
            self.wake.wait(timeout=0.5)
            self.wake.clear()
            return
        text, idx, my_gen, voice, speed = snap
        try:
            samples, sr = kok.create(text, voice=voice, speed=speed, lang="en-us")
        except Exception:
            with self.lock:
                if self.gen == my_gen and self.cursor == idx:
                    self.cursor += 1
            return
        with self.lock:
            if self.gen != my_gen:   # seek/load/stop happened during synth
                return
        data = np.ascontiguousarray(samples, dtype="float32")
        step = max(1, int(sr * 0.05))
        stream = self._out(sr)
        aborted = False
        for i in range(0, len(data), step):
            with self.lock:
                if self.gen != my_gen or self.paused:
                    aborted = True
            if aborted:
                self._drop()   # abort flushes the buffer for an instant cut
                break
            stream.write(data[i:i + step])
        if not aborted:
            with self.lock:
                if self.gen == my_gen and self.cursor == idx:
                    self.cursor += 1
                    if self.cursor >= len(self.sentences):
                        self.paused = True   # natural end-of-document stop


player = Player()

PAGE = """<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>PDF Reader</title><style>
:root{color-scheme:dark}
body{margin:0;font:15px/1.5 -apple-system,system-ui,sans-serif;background:#15151a;color:#eaeaf0;
 display:flex;flex-direction:column;height:100vh;box-sizing:border-box;padding:14px 16px;gap:12px}
#bar{display:flex;align-items:center;gap:8px;justify-content:center}
button{font-size:20px;background:#26262e;color:#eaeaf0;border:0;border-radius:10px;
 padding:10px 14px;cursor:pointer;line-height:1}button:hover{background:#33333d}
button:active{transform:translateY(1px)}
#play{font-size:24px;background:#3a6df0}#play:hover{background:#4c7bf5}
.spd{font-size:13px;padding:8px 10px}
#meta{text-align:center;font-size:12px;color:#9a9aa8}
#now{flex:1;overflow:auto;font-size:20px;line-height:1.6;display:flex;align-items:center;
 justify-content:center;text-align:center;padding:8px}
</style></head><body>
<div id=now>…</div>
<div id=meta></div>
<div id=bar>
 <button title="back" onclick="c('prev')">⏮</button>
 <button id=play title="play/pause" onclick="c('toggle')">▶</button>
 <button title="forward — skip junk" onclick="c('next')">⏭</button>
 <button title="stop" onclick="c('stop')">■</button>
 <button class=spd onclick="c('speed?v='+dn())">‹ slower</button>
 <button class=spd onclick="c('speed?v='+up())">faster ›</button>
</div>
<script>
let spd=1.0;
function up(){spd=Math.min(2,Math.round((spd+0.1)*10)/10);return spd}
function dn(){spd=Math.max(0.5,Math.round((spd-0.1)*10)/10);return spd}
async function c(cmd){const r=await fetch('/'+cmd,{method:'POST'});render(await r.json())}
function render(s){spd=s.speed;
 document.getElementById('play').textContent=s.playing?'⏸':'▶';
 document.getElementById('now').textContent=s.sentence||'(nothing loaded)';
 document.getElementById('meta').textContent=s.total?
  ((s.index+1)+' / '+s.total+' · '+s.voice+' · '+s.speed.toFixed(1)+'×'):''}
async function poll(){try{render(await(await fetch('/status')).json())}catch(e){}}
setInterval(poll,500);poll();
document.addEventListener('keydown',e=>{
 if(e.key===' '){e.preventDefault();c('toggle')}
 else if(e.key==='ArrowRight')c('next')
 else if(e.key==='ArrowLeft')c('prev')});
</script></body></html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _ok(self):
        self._send(200, json.dumps(player.status()), "application/json")

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif path == "/status":
            self._ok()
        else:
            self._send(404, "not found")

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        n = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        p = u.path
        if p == "/load":
            parts = body.split("\t", 2)
            voice = parts[0] if len(parts) > 0 and parts[0] else None
            speed = float(parts[1]) if len(parts) > 1 and parts[1] else None
            sents = [s for s in parts[2].split("\x1f") if s.strip()] if len(parts) > 2 else []
            player.load(sents, voice, speed)
        elif p == "/play":
            player.play()
        elif p == "/pause":
            player.pause()
        elif p == "/toggle":
            player.toggle()
        elif p == "/next":
            player.seek(1)
        elif p == "/prev":
            player.seek(-1)
        elif p == "/stop":
            player.stop()
        elif p == "/speed":
            try:
                player.set_speed(float(q.get("v", ["1.0"])[0]))
            except ValueError:
                pass
        else:
            return self._send(404, "not found")
        self._ok()

    def log_message(self, *a):
        pass


def main():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"reader on http://127.0.0.1:{PORT}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
