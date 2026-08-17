#!/usr/bin/env python3
"""Extract clean, readable prose from a PDF for text-to-speech.

Emits one sentence per line on stdout. Drops the junk you don't want read
aloud: page numbers and running headers/footers. Both are stripped ONLY in each
page's header/footer zone (its first and last couple of non-empty lines), never
mid-body, so a stray number, a year, an acronym, or a repeated refrain inside
the text is never mistaken for furniture. De-hyphenates words split across line
breaks, reflows hard-wrapped lines into sentences, and caps runaway sentences.

  pdf_extract.py FILE [PAGES]     PAGES = "3-10", "5", or "3-" (to end); 1-based

Scanned image PDFs have no extractable text; this exits non-zero and says so.
Run with no args to self-test.
"""
import re
import sys
from collections import Counter

ZONE = 2       # header/footer zone: first / last N non-empty lines of a page
SENT_CAP = 350  # split runaway "sentences" longer than this (also dodges the
                # Kokoro ~510-phoneme per-utterance truncation)

# A line that is ONLY page furniture: a bare number, roman numeral, "Page N",
# "N / M", or "- N -". Applied only inside the header/footer zone (see above),
# so a bare "2020" or "IV" in the body is safe.
_PAGE_NUM = re.compile(
    r"""^\s*(
        \d{1,4}
      | [ivxlcdm]{1,7}
      | page\s+\d{1,4}(\s+of\s+\d{1,4})?
      | \d{1,4}\s*/\s*\d{1,4}
      | -\s*\d{1,4}\s*-
    )\s*$""",
    re.IGNORECASE | re.VERBOSE,
)


def _norm(line):
    return re.sub(r"\s+", " ", line).strip()


def _page_range(pages, n):
    """1-based inclusive "N", "N-M", or "N-" (to end) -> 0-based [lo, hi)."""
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
    """Indices of the first and last ZONE non-empty lines (the furniture zone)."""
    idx = [k for k, ln in enumerate(lines) if _norm(ln)]
    return set(idx[:ZONE] + idx[-ZONE:])


def _running(pages_lines, n_pages):
    """Zone lines that repeat across many pages: running headers/footers.

    Counted only within the furniture zone, so a short line that recurs in the
    body (a chorus, a per-section label) is never collected.
    """
    if n_pages < 3:
        return set()
    counts = Counter()
    for lines in pages_lines:
        zone = _zone_indices(lines)
        for t in {_norm(lines[k]) for k in zone}:
            if 0 < len(t) <= 80:
                counts[t] += 1
    threshold = max(3, int(n_pages * 0.4))
    return {t for t, c in counts.items() if c >= threshold}


def _cap(sentences):
    """Split any runaway sentence on whitespace into <= SENT_CAP-char pieces.

    Guards the pathological case where sentence splitting fails to break at all
    (all-lowercase prose, non-Latin scripts) and the whole page would otherwise
    become one giant utterance that TTS truncates and you can't skip through.
    """
    out = []
    for s in sentences:
        if len(s) <= SENT_CAP:
            out.append(s)
            continue
        cur = ""
        for w in s.split():
            if cur and len(cur) + 1 + len(w) > SENT_CAP:
                out.append(cur)
                cur = w
            else:
                cur = f"{cur} {w}".strip()
        if cur:
            out.append(cur)
    return out


def extract_sentences(path, pages=None):
    import unicodedata
    from pypdf import PdfReader

    reader = PdfReader(path)
    n = len(reader.pages)
    lo, hi = _page_range(pages, n)

    pages_lines = [
        (reader.pages[i].extract_text() or "").splitlines() for i in range(lo, hi)
    ]
    running = _running(pages_lines, hi - lo)

    kept = []
    for lines in pages_lines:
        zone = _zone_indices(lines)
        for k, ln in enumerate(lines):
            nl = _norm(ln)
            if not nl:
                continue
            if k in zone and (_PAGE_NUM.match(nl) or nl in running):
                continue   # furniture, dropped only in the header/footer zone
            kept.append(ln)

    text = unicodedata.normalize("NFKC", "\n".join(kept))   # expand ﬁ/ﬂ ligatures
    text = re.sub(r"-\n(\w)", r"\1", text)      # join hyphenated line breaks (also fuses 2019-\n2020)
    text = re.sub(r"\s*\n\s*", " ", text)       # unwrap hard line breaks
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return [], (lo, hi, n)

    # Split on a sentence ender + space + an opening char, so "e.g." and "3.5"
    # inside a sentence don't split it. Naive on abbreviations (Dr. | Smith); the
    # _cap pass backstops the opposite failure (no split at all).
    sentences = re.split(r"(?<=[.!?])\s+(?=[\"'(\[A-Z0-9])", text)
    sentences = _cap([s for s in (s.strip() for s in sentences) if s])
    return sentences, (lo, hi, n)


def _selftest():
    # page-range parsing
    assert _page_range(None, 10) == (0, 10)
    assert _page_range("5", 10) == (4, 5)
    assert _page_range("3-8", 10) == (2, 8)
    assert _page_range("3-", 10) == (2, 10)          # to end
    for bad in ["0", "10-3", "500", "abc", "-5"]:
        try:
            _page_range(bad, 10)
            assert False, f"accepted bad range {bad!r}"
        except ValueError:
            pass

    # furniture stripped only in the zone; body numbers/acronyms survive
    pages = [
        ["ACME REPORT", "Revenue was 1200 last year.", "The 2020 figure held.", "1"],
        ["ACME REPORT", "IV fluids and CD sales rose.", "It grew to 1450 total.", "2"],
        ["ACME REPORT", "A closing thought e.g. this.", "iii"],
    ]
    run = _running(pages, 3)
    assert "ACME REPORT" in run, run                 # repeated header caught (in zone)
    # simulate the keep loop
    kept = []
    for lines in pages:
        zone = _zone_indices(lines)
        for k, ln in enumerate(lines):
            nl = _norm(ln)
            if not nl or (k in zone and (_PAGE_NUM.match(nl) or nl in run)):
                continue
            kept.append(nl)
    body = " ".join(kept)
    for must in ["1200", "2020", "1450", "IV", "CD"]:      # real content survives
        assert must in body, f"data loss: {must!r} dropped\n{body}"
    assert "ACME REPORT" not in body, "header not stripped"
    assert "1" not in [k for k in kept], "page number not stripped"

    # sentence split: protect e.g. / decimals, break real boundaries
    parts = re.split(r"(?<=[.!?])\s+(?=[\"'(\[A-Z0-9])",
                     "A thought e.g. this one. Truly the last line stands.")
    assert len(parts) == 2, parts
    # runaway line gets capped
    big = "word " * 200
    assert all(len(s) <= SENT_CAP for s in _cap([big.strip()])), "cap failed"
    assert len(_cap([big.strip()])) > 1
    print("pdf_extract selftest ok")


def main(argv):
    if len(argv) < 2:
        _selftest()
        return 0
    path, pages = argv[1], (argv[2] if len(argv) > 2 else None)
    try:
        sentences, (lo, hi, n) = extract_sentences(path, pages)
    except ValueError as e:
        print(str(e), file=sys.stderr)          # bad page range: clear cause
        return 2
    except Exception as e:
        print(f"cannot read PDF: {e}", file=sys.stderr)
        return 1
    if not sentences:
        print("no extractable text (scanned image PDF? OCR is not supported)", file=sys.stderr)
        return 2
    sys.stderr.write(f"pages {lo + 1}-{hi} of {n}, {len(sentences)} sentences\n")
    sys.stdout.write("\n".join(sentences))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
