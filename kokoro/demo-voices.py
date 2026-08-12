import os, sys, select
import sounddevice as sd
from kokoro_onnx import Kokoro

K = os.path.dirname(os.path.abspath(__file__))
kok = Kokoro(os.path.join(K, "kokoro-v1.0.onnx"), os.path.join(K, "voices-v1.0.bin"))

prefix = sys.argv[1] if len(sys.argv) > 1 else ""
voices = sorted(v for v in kok.get_voices() if v.startswith(prefix))
if not voices:
    print(f"no voices match '{prefix}' (try af / am / bf / bm)")
    sys.exit(1)

LINE = "Hi, I'm {}. This is how your summaries would sound in my voice."
_cache = {}


def synth(v):  # cache so re-visiting a voice is instant
    if v not in _cache:
        _cache[v] = kok.create(LINE.format(v.split("_", 1)[1]), voice=v, speed=1.0, lang="en-us")
    return _cache[v]


def playing():
    try:
        return sd.get_stream().active
    except Exception:
        return False


# No TTY (piped): just play each once, in order.
if not sys.stdin.isatty():
    for v in voices:
        print("  " + v, flush=True)
        s, sr = synth(v); sd.play(s, sr); sd.wait()
    sys.exit(0)

import termios, tty


def read_key(timeout):
    if not select.select([sys.stdin], [], [], timeout)[0]:
        return None
    c = sys.stdin.read(1)
    if c == "\x1b":  # arrow keys arrive as ESC [ C / ESC [ D
        if select.select([sys.stdin], [], [], 0.002)[0]:
            seq = sys.stdin.read(2)
            if seq == "[C": return "next"
            if seq == "[D": return "prev"
        return None
    if c in ("q", "\x03"): return "quit"
    if c in (" ", "n", "j", "\r"): return "next"
    if c in ("p", "k"): return "prev"
    return None


print(f"{len(voices)} voices.  →/space next   ←/p back   q quit.  Set one with: voice use <name>\n")
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
try:
    tty.setcbreak(fd)
    idx = 0
    while 0 <= idx < len(voices):
        v = voices[idx]
        sys.stdout.write(f"\r  [{idx + 1}/{len(voices)}] {v}            \n")
        sys.stdout.flush()
        s, sr = synth(v)
        sd.play(s, sr)
        action = None
        while playing():
            k = read_key(0.05)
            if k:
                action = k
                break
        sd.stop()
        if action == "quit":
            break
        idx = max(0, idx - 1) if action == "prev" else idx + 1
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
    sd.stop()
    print()
