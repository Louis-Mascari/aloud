import os, re, socket, threading, queue
import numpy as np
import sounddevice as sd
from kokoro_onnx import Kokoro

K = os.path.dirname(os.path.abspath(__file__))
SOCK = os.path.join(K, "daemon.sock")
STOP = os.path.join(K, "interrupt")  # touched by `voice stop` to cut playback

DEF_VOICE = os.environ.get("VOICE_KOKORO_VOICE", "af_heart")
DEF_SPEED = float(os.environ.get("VOICE_KOKORO_SPEED", "1.0"))

kok = Kokoro(os.path.join(K, "kokoro-v1.0.onnx"), os.path.join(K, "voices-v1.0.bin"))

_stream = None   # one persistent output stream, reused across sentences
_stream_sr = None


def sentences(text):
    return [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s]


def interrupted(since):
    return os.path.exists(STOP) and os.path.getmtime(STOP) > since


def output_stream(sr):
    # One persistent stream fed sentence-by-sentence. A fresh sd.play() per
    # sentence dropped the leading samples during the device's cold-start ramp
    # ("ood" for "Good") and clicked at each boundary. The 0.15s silence primer
    # on open absorbs that ramp so the first word survives.
    global _stream, _stream_sr
    if _stream is None or _stream_sr != sr:
        drop_stream()
        # latency="high" gives a larger buffer so a slow synth between sentences
        # doesn't starve the stream and glitch; barge-in still cuts via abort().
        _stream = sd.OutputStream(samplerate=sr, channels=1, dtype="float32", latency="high")
        _stream.start()
        _stream_sr = sr
        _stream.write(np.zeros(int(sr * 0.15), dtype="float32"))
    return _stream


def drop_stream():
    global _stream, _stream_sr
    if _stream is not None:
        try:
            _stream.abort()
            _stream.close()
        except Exception:
            pass
    _stream = None
    _stream_sr = None


def speak(text, voice, speed):
    # Synthesize the next sentence on a worker thread while the current one plays,
    # so playback is gapless. Blocking writes into the persistent stream pace to
    # real time; checking `interrupted` between chunks keeps barge-in responsive.
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
            # Never block forever on a full queue: wake to recheck the interrupt
            # so barge-in doesn't strand this thread in the long-lived daemon.
            while True:
                if interrupted(since):
                    return
                try:
                    q.put((samples, sr), timeout=0.2)
                    break
                except queue.Full:
                    pass
        try:
            q.put(None, timeout=0.2)
        except queue.Full:
            pass

    threading.Thread(target=produce, daemon=True).start()

    while True:
        item = q.get()
        if item is None:
            return
        if interrupted(since):
            drop_stream()
            return
        samples, sr = item
        stream = output_stream(sr)
        data = np.ascontiguousarray(samples, dtype="float32")
        step = max(1, int(sr * 0.05))
        for i in range(0, len(data), step):
            if interrupted(since):
                drop_stream()  # abort flushes the buffer for an instant cut
                return
            stream.write(data[i:i + step])


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
