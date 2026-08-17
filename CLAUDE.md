# Working in this repo (for coding agents)

**aloud** is a collection of local "listen instead of read" tools sharing one
Kokoro TTS engine. Tools are separate top-level dirs; `kokoro/` is the shared
engine. ("Spit It Out" is the PDF-reader app's name, not the collection's.)

- **claude-voice** (`hooks/`, `lib/`, `bin/voice`, `wezterm/`) — async spoken
  summaries + tab state for Claude Code in WezTerm. Hooks write state files;
  `bin/voice` + `lib/*.sh` read them; `kokoro/daemon.py` is the warm
  notification-TTS daemon.
- **PDF reader** (`pdf-reader/`) — the read-along. `bin/pdf-read` / `bin/pdf-ctl`
  drive `pdf-reader/reader.py` (an HTTP daemon on `127.0.0.1:8477`) that extracts
  with `pdf-reader/pdf_extract.py` and serves the split-view UI in
  `pdf-reader/weblib/`. The desktop app is "Spit It Out".

## The one gotcha that will waste your time

**Nothing runs from the repo.** `setup-kokoro.sh` copies the Python + `weblib/`
into `~/.claude/voice/kokoro/`, and the daemon runs from there (that's where the
model weights and the `.venv` live). Editing a repo file changes nothing until
you copy it over:

```bash
K=~/.claude/voice/kokoro   # the reader shares the Kokoro runtime (venv + weights)
cp pdf-reader/reader.py pdf-reader/pdf_extract.py "$K"/
cp pdf-reader/weblib/reader.html "$K"/weblib/
```

`bin/pdf-read`, `bin/pdf-ctl`, `bin/voice` run from the repo (they're on PATH via
`~/.zshrc`), so bash edits take effect immediately; Python/HTML edits need the copy.

## Run / test the reader

```bash
K=~/.claude/voice/kokoro; PY=$K/.venv/bin/python
$PY pdf-reader/pdf_extract.py                  # extraction self-test (asserts)
pkill -f "$K/reader.py"; $PY $K/reader.py &     # restart the daemon after a .py edit
pdf-read ~/Downloads/some.pdf                  # extract + load + open the UI
pdf-ctl status                                 # {playing,index,total,sentence,...}
```
Browser-test the UI at `http://127.0.0.1:8477/` (Playwright MCP works well).

## Invariants — don't regress these

- **Daemon security**: `reader.py` binds loopback and guards every request with a
  `Host` allowlist + `Sec-Fetch-Site` check (`_guard`). This stops a visited web
  page from driving the daemon or reading local PDFs via `/pdf` (DNS-rebinding).
  Keep it.
- **Extraction reading order**: use pypdf's own text order (it handles
  multi-column). A naive y-sort interleaves columns. Drop headers/footers by
  composed device y (`tm`×`cm`), not by string-matching footer text.
- **Highlight**: never `freePage` the page the current sentence is on, and
  repaint if it re-renders — otherwise the follow-scroll detaches the highlighted
  nodes. The highlight retries until it paints (`hlIndex`).
- **No per-document hacks in extraction.** Fixes must generalize (geometry,
  repeated-line detection), not target one PDF's footer text.

## Conventions

- US English everywhere (identifiers, tests, prose).
- PUA ligature literals (U+F000–F004) as `\uXXXX` escapes in source, never raw
  invisible chars — they corrupt on edit. There's a `_PUA` map in
  `pdf_extract.py` and a matching one in `reader.html`.
- Commit trailers include `Co-Authored-By`; no "generated with" footer in PR
  bodies. Code comments explain *why*, not what changed.

## Docs

- `README.md` — human-facing, feature-first.
- `RECIPES.md` — binding `voice stop` / `pdf-ctl` to hotkeys.
- `docs/architecture.md` — the claude-voice event/state map.
- `wezterm/INTEGRATE.md` — wiring the WezTerm layer.
