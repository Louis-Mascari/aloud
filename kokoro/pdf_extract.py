#!/usr/bin/env python3
"""Extract clean, readable prose from a PDF for text-to-speech.

Returns (sentence, page) pairs. Drops the junk you don't want read aloud (page
numbers, running headers/footers) but only in each page's header/footer zone,
never mid-body, so a stray number, year, acronym, or repeated refrain in the
text is never mistaken for furniture. Reflows wrapped prose lines back into
sentences while keeping headings and table rows as their own short units (so
they read and skip cleanly instead of fusing into one long run). Expands
Private-Use-Area ligatures and caps runaway sentences.

CLI (mainly for debugging): prints "page<TAB>sentence" per line.
  pdf_extract.py FILE [PAGES]     PAGES = "3-10", "5", or "3-" (to end); 1-based
Run with no args to self-test.
"""
import re
import sys
from collections import Counter

ZONE = 2        # header/footer zone: first / last N non-empty lines of a page
SENT_CAP = 350  # split runaway "sentences" longer than this (also dodges the
                # Kokoro ~510-phoneme per-utterance truncation)

# Explicit page labels are furniture ANYWHERE on the page: "page N", "N of M",
# "N / M", "- N -" never occur as body prose, so they're safe to strip wherever
# pypdf places them in the line order.
_PAGE_LABEL = re.compile(
    r"^\s*(page\s+\d{1,4}(\s+of\s+\d{1,4})?|\d{1,4}\s*/\s*\d{1,4}|-\s*\d{1,4}\s*-)\s*$",
    re.IGNORECASE)
# A bare number or roman numeral is only furniture in the header/footer zone;
# mid-body it could be a year, price, or table cell.
_PAGE_BARE = re.compile(r"^\s*(\d{1,4}|[ivxlcdm]{1,7})\s*$", re.IGNORECASE)

# Subset fonts encode ligatures in the Private Use Area (Adobe convention), which
# NFKC can't expand. Map the common ones; any leftover PUA/control glyph becomes a
# space so no unreadable "tofu" reaches the voice.
_PUA = {"\uF000": "ff", "\uF001": "fi", "\uF002": "fl", "\uF003": "ffi", "\uF004": "ffl"}
_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[\"'(\[A-Z0-9])")


def _norm(line):
    return re.sub(r"\s+", " ", line).strip()


def _clean_glyphs(text):
    import unicodedata
    text = text.translate(str.maketrans(_PUA))
    text = unicodedata.normalize("NFKC", text)
    return "".join(
        c if c == "\n" or unicodedata.category(c) not in ("Co", "Cc", "Cf") else " "
        for c in text
    )


def _page_range(pages, n):
    if not pages:
        return 0, n
    try:
        a, sep, b = pages.partition("-")
        lo = int(a) - 1
        hi = (int(b) if b else n) if sep else int(a)
    except ValueError:
        raise ValueError(f"bad page range {pages!r}: use N, N-M, or N-")
    if not (0 <= lo < hi <= n):
        raise ValueError(f"page range {pages!r} is outside 1-{n}")
    return lo, hi


def _zone_indices(lines):
    idx = [k for k, ln in enumerate(lines) if _norm(ln)]
    return set(idx[:ZONE] + idx[-ZONE:])


def _running(pages_lines, n_pages):
    """Short lines repeating across many pages: headers, footers, copyright.

    Scanned everywhere (not just the zone) because pypdf doesn't always emit a
    footer as the first/last line. The >=50% threshold keeps it from eating a
    body line that merely recurs a handful of times.
    """
    if n_pages < 3:
        return set()
    counts = Counter()
    for lines in pages_lines:
        for t in {_norm(x) for x in lines if 0 < len(_norm(x)) <= 80}:
            counts[t] += 1
    threshold = max(3, int(n_pages * 0.5))
    return {t for t, c in counts.items() if c >= threshold}


def _is_wrap(prev, nxt):
    """True when `nxt` is a soft-wrap continuation of `prev`, not a new line unit.

    Long lines with no terminal punctuation are wrapped prose (join). Short lines
    (headings, table cells, list items) stay separate unless the next clearly
    continues a sentence (starts lowercase).
    """
    if prev[-1] in ".!?:;":
        return False
    if not (nxt[:1].isalnum()):
        return False
    return nxt[:1].islower() or len(prev) >= 55


def _merge_wrapped(lines):
    out, buf = [], ""
    for ln in lines:
        ln = _norm(ln)
        if not ln:
            continue
        if buf and _is_wrap(buf, ln):
            buf += " " + ln
        else:
            if buf:
                out.append(buf)
            buf = ln
    if buf:
        out.append(buf)
    return out


def _cap(s):
    """Split a runaway line on whitespace into <= SENT_CAP-char pieces."""
    if len(s) <= SENT_CAP:
        return [s]
    out, cur = [], ""
    for w in s.split():
        if cur and len(cur) + 1 + len(w) > SENT_CAP:
            out.append(cur)
            cur = w
        else:
            cur = f"{cur} {w}".strip()
    if cur:
        out.append(cur)
    return out


def _page_body_text(page):
    """Text with the top/bottom 8% band dropped, by glyph y-position.

    pypdf often glues the footer (copyright, page number) onto body text on the
    same extracted line, so line-content filtering can't isolate it. Filtering by
    vertical position removes headers/footers regardless of how lines are joined.
    Newlines (y==0 marker calls) are kept so line structure survives.
    """
    try:
        h = float(page.mediabox.height)
    except Exception:
        h = 792.0
    lo, hi = h * 0.08, h * 0.92
    parts = []

    def visit(text, cm, tm, font, size):
        y = tm[5]
        if y == 0 or lo < y < hi:
            parts.append(text)

    try:
        page.extract_text(visitor_text=visit)
    except Exception:
        return page.extract_text() or ""     # visitor unsupported: fall back to plain
    return "".join(parts)


def extract_sentences(path, pages=None):
    from pypdf import PdfReader

    reader = PdfReader(path)
    n = len(reader.pages)
    lo, hi = _page_range(pages, n)

    pages_lines = [_page_body_text(reader.pages[i]).splitlines() for i in range(lo, hi)]
    running = _running(pages_lines, hi - lo)

    result = []   # (sentence, page)
    for i, lines in enumerate(pages_lines):
        pageno = lo + i + 1
        zone = _zone_indices(lines)
        kept = []
        for k, ln in enumerate(lines):
            nl = _norm(ln)
            if not nl or nl in running or _PAGE_LABEL.match(nl):
                continue
            if k in zone and _PAGE_BARE.match(nl):
                continue
            kept.append(ln)
        cleaned = _clean_glyphs("\n".join(kept))
        cleaned = re.sub(r"-\n(\w)", r"\1", cleaned)      # join hyphenated line breaks
        page_lines = [ln for ln in cleaned.split("\n") if _norm(ln)]
        for unit in _merge_wrapped(page_lines):           # reflow wrapped prose
            for part in _SPLIT.split(unit):               # split real sentences
                part = part.strip()
                if part:
                    for piece in _cap(part):
                        result.append((piece, pageno))
    return result, (lo, hi, n)


def _selftest():
    assert _page_range(None, 10) == (0, 10)
    assert _page_range("3-", 10) == (2, 10)
    assert _page_range("5", 10) == (4, 5)
    for bad in ["0", "10-3", "500", "abc", "-5"]:
        try:
            _page_range(bad, 10); assert False, bad
        except ValueError:
            pass

    for lbl in ["Page 2 of 3", "3 / 9", "- 7 -"]:            # furniture anywhere
        assert _PAGE_LABEL.match(_norm(lbl)), lbl
    for bare in ["1", "iii", "42"]:                          # furniture only in zone
        assert _PAGE_BARE.match(_norm(bare)) and not _PAGE_LABEL.match(_norm(bare)), bare
    for keep in ["Introduction", "10x growth", "It grew."]:  # never furniture
        assert not _PAGE_LABEL.match(_norm(keep)) and not _PAGE_BARE.match(_norm(keep)), keep
    # a copyright line repeating on most pages is caught anywhere (not just the zone)
    cw = _running([["Body one.", "© 2025 Acme"]] * 5 + [["© 2025 Acme", "Body two."]] * 5, 10)
    assert "© 2025 Acme" in cw, cw

    # PUA ligatures expand; stray private-use glyphs become spaces; \n preserved
    assert _clean_glyphs("The \uF001rst \uF002ow") == "The first flow"
    assert _clean_glyphs("ab\nc") == "a b\nc"

    # wrapped prose merges; headings / rows stay their own unit
    merged = _merge_wrapped([
        "This is a long wrapped line of prose that keeps",
        "going here.", "Heading", "Body starts here."])
    assert merged == ["This is a long wrapped line of prose that keeps going here.",
                      "Heading", "Body starts here."], merged
    # a short row followed by lowercase continuation joins (reads together)
    assert _merge_wrapped(["Horizontal line", "y equals b."]) == ["Horizontal line y equals b."]

    # sentence split protects e.g. / decimals, breaks real boundaries
    assert len(_SPLIT.split("A thought e.g. this. Truly last stands.")) == 2
    assert all(len(x) <= SENT_CAP for x in _cap("word " * 200))
    print("pdf_extract selftest ok")


def main(argv):
    if len(argv) < 2:
        _selftest()
        return 0
    path, pages = argv[1], (argv[2] if len(argv) > 2 else None)
    try:
        result, (lo, hi, nn) = extract_sentences(path, pages)
    except ValueError as e:
        print(str(e), file=sys.stderr); return 2
    except Exception as e:
        print(f"cannot read PDF: {e}", file=sys.stderr); return 1
    if not result:
        print("no extractable text (scanned image PDF? OCR is not supported)", file=sys.stderr)
        return 2
    sys.stderr.write(f"pages {lo + 1}-{hi} of {nn}, {len(result)} sentences\n")
    sys.stdout.write("\n".join(f"{p}\t{t}" for t, p in result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
