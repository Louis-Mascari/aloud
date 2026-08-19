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
    r"^\s*(page\s+\d{1,4}(\s+of\s+\d{1,4})?|pages?|pg|\d{1,4}\s*/\s*\d{1,4}|-\s*\d{1,4}\s*-)[.)]?\s*$",
    re.IGNORECASE)
# A bare number is only furniture in the header/footer zone; mid-body it could be
# a year/price/table cell. Roman numerals are excluded ("[ivxlcdm]+" eats Civil,
# MIDI, DVD, mix); digit pagination covers almost everything.
_PAGE_BARE = re.compile(r"^\s*\d{1,4}\s*$")

# Subset fonts encode ligatures in the Private Use Area (Adobe convention), which
# NFKC can't expand. Map the common ones; any leftover PUA/control glyph becomes a
# space so no unreadable "tofu" reaches the voice.
_PUA = {"\uF000": "ff", "\uF001": "fi", "\uF002": "fl", "\uF003": "ffi", "\uF004": "ffl"}
# Split on a sentence ender + space + an opening letter/quote. Digits are NOT a
# boundary trigger, so "Fig. 3", "No. 5", "et al. 2020" don't shatter. A
# post-split repair (in extract_sentences) rejoins pieces that start lowercase,
# with punctuation, or with a digit — the leftover abbreviation fragments.
_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[\"'(\[A-Z])")


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


# Drop the header/footer band by device y (fraction of page height). Asymmetric
# because footers/page-numbers sit very low (~3%) while body can start high
# (~95%): a wide top band eats real first lines. Measured so footers and a
# top-edge "Page" label are removed but body survives.
_BAND_LO, _BAND_HI = 0.05, 0.97


def _single_column(frags, pw):
    """True if no text line has fragments in both the left and right halves.

    A two-column layout has side-by-side text at the same y; single-column prose
    never does. pypdf's own order isn't reliably top-to-bottom, so single-column
    pages are re-ordered by position (fixes a top block emitted late), while
    multi-column pages keep pypdf's order (a naive y-sort interleaves columns).
    """
    from collections import defaultdict
    lines = defaultdict(list)
    for x, y, _ in frags:
        lines[round(y / 6)].append(x)
    L, R = pw * 0.45, pw * 0.55
    return not any(any(x < L for x in xs) and any(x > R for x in xs) for xs in lines.values())


def _lines_by_y(frags):
    """Group position-ordered fragments into lines by y proximity; join each L→R."""
    out, cur, cy = [], [], None
    for x, y, t in frags:
        if cy is not None and abs(y - cy) <= 6:
            cur.append((x, t))
        else:
            if cur:
                out.append(cur)
            cur, cy = [(x, t)], y
    if cur:
        out.append(cur)
    # Space-join fragments: pypdf's visitor emits one fragment per word with no
    # separator (Google Docs and many exporters lay out word-by-word), so a raw
    # "".join glues them. _norm later collapses any doubled spaces.
    return "\n".join(" ".join(t for _, t in sorted(l)) for l in out)


def _page_body_text(page):
    """Body text with the header/footer band dropped, in correct reading order.

    Collect in-band fragments with position (device x/y composed through the CTM,
    so it's right even under a cm/XObject transform). Single-column pages are
    sorted top-to-bottom; multi-column pages keep pypdf's order (de-glued on
    >1-line y jumps) so columns aren't interleaved.
    """
    try:
        rot = int(getattr(page, "rotation", 0) or 0) % 360
    except Exception:
        rot = 0
    if rot in (90, 270):
        return page.extract_text() or ""     # y-band is meaningless on a rotated page
    try:
        h = float(page.mediabox.height)
        pw = float(page.mediabox.width)
    except Exception:
        h, pw = 792.0, 612.0
    lo, hi = h * _BAND_LO, h * _BAND_HI
    frags = []   # (x, y, text) in pypdf visitor order

    def visit(text, cm, tm, font, size):
        if not text.strip():
            return
        y = tm[4] * cm[1] + tm[5] * cm[3] + cm[5]
        x = tm[4] * cm[0] + tm[5] * cm[2] + cm[4]
        if lo < y < hi:
            frags.append((x, y, text))

    try:
        page.extract_text(visitor_text=visit)
    except Exception:
        return page.extract_text() or ""     # visitor unsupported: fall back to plain
    if not frags:
        return ""

    if _single_column(frags, pw):
        frags.sort(key=lambda f: (-f[1], f[0]))   # top-to-bottom, then left-to-right
        return _lines_by_y(frags)
    # multi-column: keep pypdf order, split lines on a >1-line y jump (de-glue)
    parts, prev_y = [], None
    for x, y, t in frags:
        if prev_y is not None and abs(prev_y - y) > 8:
            parts.append("\n" + t)      # new line
        elif parts:
            parts.append(" " + t)       # same line: space between word fragments
        else:
            parts.append(t)
        prev_y = y
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
            kept.append(nl)
        cleaned = _clean_glyphs("\n".join(kept))
        cleaned = re.sub(r"-\n(\w)", r"\1", cleaned)      # join hyphenated line breaks
        page_lines = [ln for ln in cleaned.split("\n") if _norm(ln)]
        for unit in _merge_wrapped(page_lines):           # reflow wrapped prose
            for part in _SPLIT.split(unit):               # split real sentences
                part = part.strip()
                if not part:
                    continue
                for piece in _cap(part):
                    # A piece that opens lowercase, with punctuation, or with a
                    # digit isn't a new sentence — it's the tail of the previous
                    # one the splitter over-cut ("Fig." | "3", "shows" | ", we...").
                    if (result and result[-1][1] == pageno
                            and (piece[:1].islower() or piece[:1].isdigit()
                                 or piece[0] in ",;:.)]}%")):
                        result[-1] = (result[-1][0] + " " + piece, pageno)
                    else:
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

    for lbl in ["Page 2 of 3", "3 / 9", "- 7 -", "Page", "pg", "pages"]:   # furniture anywhere
        assert _PAGE_LABEL.match(_norm(lbl)), lbl
    for bare in ["1", "42"]:                                 # bare number: furniture in zone only
        assert _PAGE_BARE.match(_norm(bare)) and not _PAGE_LABEL.match(_norm(bare)), bare
    # roman-charset words must NOT be eaten now that roman is out of _PAGE_BARE
    for keep in ["Introduction", "10x growth", "It grew.", "Civil", "MIDI", "DVD", "mix"]:
        assert not _PAGE_LABEL.match(_norm(keep)) and not _PAGE_BARE.match(_norm(keep)), keep
    # digit after an abbreviation must not trigger a split
    assert len(_SPLIT.split("See Fig. 3 for details.")) == 1
    # a copyright line repeating on most pages is caught anywhere (not just the zone)
    cw = _running([["Body one.", "© 2025 Acme"]] * 5 + [["© 2025 Acme", "Body two."]] * 5, 10)
    assert "© 2025 Acme" in cw, cw

    # PUA ligatures expand; stray private-use glyphs become spaces; \n preserved
    assert _clean_glyphs("The \uF001rst \uF002ow") == "The first flow"
    assert _clean_glyphs("ab\nc") == "a b\nc"

    # word-granular fragments (visitor emits one word each, no separator) get
    # space-joined per line, not glued
    frags = [(0, 100, "Data"), (25, 100, "integrity"), (0, 80, "A"), (10, 80, "foundation")]
    assert _lines_by_y(frags) == "Data integrity\nA foundation", _lines_by_y(frags)

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
