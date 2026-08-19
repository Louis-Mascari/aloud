# aloud

A small collection of local, work-safe tools for people who'd rather **listen
than read** — less eye strain, fewer walls of text to get through in a day.
Everything runs on your machine (no cloud, no accounts, no IP concerns), sharing
one local [Kokoro](https://github.com/thewh1teagle/kokoro-onnx) neural voice.

## Tools

### 📄 Spit It Out — read PDFs aloud → [pdf-reader/](pdf-reader/README.md)

Read-along for PDFs: the rendered page on one side, a voice reading it on the
other. Select text on the page to read from there, watch the spoken sentence
highlight and follow along, and drive it with transport controls, 50+ voices,
light/dark, per-pane zoom, and an always-on-top mini player. Ships as a
drag-and-drop **macOS app**. 100% offline.

### 🔊 claude-voice — hear Claude Code → [docs/claude-voice.md](docs/claude-voice.md)

Claude Code speaks a short recap each turn instead of you reading walls of
terminal output; background tabs flag when they need you, and one toggle silences
everything for meetings. A menu-bar player and per-tab glyphs give you GUI
controls. Built for WezTerm — the voice half works on any terminal.

## Setup

Both tools share the local Kokoro voice engine, installed once:

```bash
./setup-kokoro.sh     # isolated venv + ~360MB model, offline from then on
```

Then follow the tool you want:
[Spit It Out (PDF reader)](pdf-reader/README.md) · [claude-voice](docs/claude-voice.md).

## Layout

| Path | What |
|------|------|
| `kokoro/` | shared TTS engine (used by every tool) |
| `pdf-reader/` | **Spit It Out** — the PDF reader |
| `hooks/`, `lib/`, `wezterm/`, `mac/swiftbar/` | **claude-voice** — terminal recaps, tab flags, menu-bar player |
| `bin/` | CLIs on your PATH — `pdf-read`, `pdf-ctl`, `voice`, `kokoro-say` |
| `mac/`, `setup-app.sh` | the Spit It Out desktop-app build |

A future tool is a new top-level directory that reuses the same engine and the
`~/.claude/voice/kokoro` runtime. Architecture and agent/dev notes:
[CLAUDE.md](CLAUDE.md).

## License

MIT — see [LICENSE](LICENSE).
