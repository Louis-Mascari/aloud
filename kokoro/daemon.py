import os, re, socket, subprocess, tempfile
import soundfile as sf
from kokoro_onnx import Kokoro

K = os.path.dirname(os.path.abspath(__file__))
SOCK = os.path.join(K, "daemon.sock")
STOP = os.path.join(K, "interrupt")  # touched by `voice stop` to cut playback

DEF_VOICE = os.environ.get("VOICE_KOKORO_VOICE", "af_heart")
DEF_SPEED = float(os.environ.get("VOICE_KOKORO_SPEED", "1.0"))

kok = Kokoro(os.path.join(K, "kokoro-v1.0.onnx"), os.path.join(K, "voices-v1.0.bin"))


def sentences(text):
    return [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s]


def speak(text, voice, speed):
    # Play one sentence at a time so audio starts after the first short chunk,
    # not after synthesizing the whole summary. Check the interrupt flag between.
    start = os.path.getmtime(STOP) if os.path.exists(STOP) else 0
    for s in sentences(text):
        if os.path.exists(STOP) and os.path.getmtime(STOP) > start:
            return
        samples, sr = kok.create(s, voice=voice, speed=speed, lang="en-us")
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            wav = f.name
        sf.write(wav, samples, sr)
        subprocess.run(["afplay", wav])
        os.unlink(wav)


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
