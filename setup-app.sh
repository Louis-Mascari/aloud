#!/usr/bin/env bash
# setup-app.sh — build a "Read Aloud" drag-and-drop app (macOS) so you can read a
# PDF without the terminal: drop it on the Dock icon, or right-click the PDF ▸
# Open With ▸ Read Aloud. With no file it reads the newest PDF in ~/Downloads.
# Re-runnable. Needs setup-kokoro.sh done first.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${1:-$HOME/Applications/Read Aloud.app}"
PDFREAD="$REPO/bin/pdf-read"

tmp="$(mktemp).applescript"
cat > "$tmp" <<APPLESCRIPT
-- Read a dropped/opened PDF (or the newest in Downloads) via claude-voice.
on readFile(posixPath)
	do shell script quoted form of "$PDFREAD" & " " & quoted form of posixPath & " >/dev/null 2>&1 &"
end readFile

on open theItems
	repeat with anItem in theItems
		readFile(POSIX path of anItem)
	end repeat
end open

on run
	set newest to do shell script "ls -t \$HOME/Downloads/*.pdf 2>/dev/null | head -1"
	if newest is "" then
		display dialog "No PDF in Downloads. Drop a PDF on this icon, or right-click a PDF ▸ Open With ▸ Read Aloud." buttons {"OK"} default button 1 with title "Read Aloud"
	else
		readFile(newest)
	end if
end run
APPLESCRIPT

rm -rf "$APP"
osacompile -o "$APP" "$tmp"
rm -f "$tmp"
echo "Built: $APP"
echo "Drag it to your Dock. Then drop a PDF on it, or right-click a PDF ▸ Open With ▸ Read Aloud."
