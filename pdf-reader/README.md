# Spit It Out — read PDFs aloud

Read-along for PDFs, **100% offline** (nothing leaves your machine, so work/NDA
documents are fine). The rendered page on one side, a natural
[Kokoro](https://github.com/thewh1teagle/kokoro-onnx) voice reading it on the
other — with the spoken sentence highlighted and following along.

Part of the [aloud](../README.md) collection; shares the Kokoro engine in
[`../kokoro/`](../kokoro). Run [`../setup-kokoro.sh`](../setup-kokoro.sh) once first.

## The app (no terminal)

Build the **Spit It Out** desktop app once, then never touch the terminal:

```bash
../setup-app.sh        # builds "Spit It Out.app" with its icon
```

Three ways to open a PDF with it:
- **Drop a PDF** on its Dock icon.
- Right-click any PDF in Finder ▸ **Open With ▸ Spit It Out**.
- **Launch it** (Dock / Spotlight) to get a **Choose-a-PDF** file picker.

## From a terminal

```bash
pdf-read ~/aloud/pdf-reader/sample/aloud-sample.pdf   # try the included sample
pdf-read ~/Downloads/paper.pdf          # whole document
pdf-read ~/Downloads/paper.pdf 3-40     # pages 3–40 (skip cover, TOC, references)
```

Both open the same split-view reader in your browser.

## The reader

- **Split view** — the real PDF beside the text; drag the divider to resize,
  **swap** sides, **stack** them, or collapse either. Your layout is remembered.
- **Select text on the PDF → the voice reads from there.** The current sentence
  highlights on the page and the view follows it.
- **Transport** — play/pause, skip back/forward, stop (keeps your place),
  slower/faster. Keys: **Space**, **←**, **→**. Skip-forward blows past junk.
- **50+ voices** grouped by accent and gender, labelled with their Kokoro quality
  grade where one is published (A is best), with a **★ Recommended** group of the
  most natural voices up top; switch live.
- **Per-pane zoom** — the PDF and the reader text zoom independently (buttons or
  ⌘-scroll on the PDF).
- **Float** — pop the controls into an always-on-top mini window (Document
  Picture-in-Picture) to drive it while you read elsewhere.
- **Light / dark** — follows your OS, with a manual toggle.

## Control from anywhere

```bash
pdf-ctl play | pause | next | prev | stop | speed 1.2
```

Bind these to global hotkeys (so you can drive it while another window is
focused) via [`../RECIPES.md`](../RECIPES.md).

## How it reads cleanly

Headers, footers, and page numbers are dropped from what's spoken (by page
position, so it survives odd layouts). Single-column pages are read top-to-bottom;
genuine two-column pages keep their column order. A page range skips whole
sections. **Scanned image PDFs** have no extractable text and aren't supported
(no OCR).

## Under the hood

The PDF is rendered by [PDF.js](https://github.com/mozilla/pdf.js) (Apache-2.0),
vendored in [`weblib/`](weblib) and served from `127.0.0.1` (Host-checked), so it
stays fully offline. `reader.py` is the HTTP reader daemon; `pdf_extract.py` is
the text extractor. Architecture and dev notes: [`../CLAUDE.md`](../CLAUDE.md).
