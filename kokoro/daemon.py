import os, re, socket, time, threading, queue
import sounddevice as sd
from kokoro_onnx import Kokoro

K = os.path.dirname(os.path.abspath(__file__))
SOCK = os.path.join(K, "daemon.sock")
STOP = os.path.join(K, "interrupt")  # touched by `voice stop` to cut playback

DEF_VOICE = os.environ.get("VOICE_KOKORO_VOICE", "af_heart")
DEF_SPEED = float(os.environ.get("VOICE_KOKORO_SPEED", "1.0"))

kok = Kokoro(os.path.join(K, "kokoro-v1.0.onnx"), os.path.join(K, "voices-v1.0.bin"))


def sentences(text):
    return [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s]


def interrupted(since):
    return os.path.exists(STOP) and os.path.getmtime(STOP) > since


def speak(text, voice, speed):
    # Synthesize the next sentence on a worker thread while the current one plays,
    # so playback is gapless. Play via sounddevice (cross-platform, interruptible).
    since = os.path.getmtime(STOP) if os.path.exists(STOP) else 0.0
    q = queue.Queue(maxsize=2)

    def produce():
        for s in sentences(text):
            if interrupted(since):
                break
            try:
                samples, sr = kok.create(s, voice=voice, speed=speed, lang="en-us")
            except Exception:
                continue
            q.put((samples, sr))
        q.put(None)

    threading.Thread(target=produce, daemon=True).start()

    while True:
        item = q.get()
        if item is None or interrupted(since):
            sd.stop()
            return
        samples, sr = item
        sd.play(samples, sr)
        while True:
            try:
                if not sd.get_stream().active:
                    break
            except Exception:
                break
            if interrupted(since):
                sd.stop()
                return
            time.sleep(0.03)


if os.path.exists(SOCK):
    os.unlink(SOCK)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(SOCK)
srv.listen(8)
print("kokoro daemon ready", flush=True)

while True:
    conn, _ = srv.accept()
    data = conn.recv(65536).decode("utf-8", "replace")
    conn.close()
    try:
        voice, speed, text = data.split("\t", 2)
        speak(text, voice or DEF_VOICE, float(speed or DEF_SPEED))
    except Exception as e:
        print("err:", e, flush=True)
