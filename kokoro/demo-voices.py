import os, sys
import sounddevice as sd
from kokoro_onnx import Kokoro

K = os.path.dirname(os.path.abspath(__file__))
kok = Kokoro(os.path.join(K, "kokoro-v1.0.onnx"), os.path.join(K, "voices-v1.0.bin"))

prefix = sys.argv[1] if len(sys.argv) > 1 else ""
voices = sorted(v for v in kok.get_voices() if v.startswith(prefix))
if not voices:
    print(f"no voices match '{prefix}' (try af / am / bf / bm)")
    sys.exit(1)

print(f"{len(voices)} voices. Ctrl-C to stop. Set one with: voice use <name>\n")
line = "Hi, I'm {}. This is how your summaries would sound in my voice."
try:
    for v in voices:
        print("  " + v, flush=True)  # exact id to pass to `voice use`
        s, sr = kok.create(line.format(v.split("_", 1)[1]), voice=v, speed=1.0, lang="en-us")
        sd.play(s, sr)
        sd.wait()
except KeyboardInterrupt:
    sd.stop()
    print("\nstopped")
