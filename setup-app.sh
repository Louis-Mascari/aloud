#!/usr/bin/env bash
# setup-app.sh — build the "Spit It Out" drag-and-drop app (macOS) so you can read
# a PDF without the terminal: drop it on the Dock icon, or right-click the PDF ▸
# Open With ▸ Spit It Out. With no file it reads the newest PDF in ~/Downloads.
# Re-runnable. Needs setup-kokoro.sh done first.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${1:-$HOME/Applications/Spit It Out.app}"
PDFREAD="$REPO/bin/pdf-read"

tmp="$(mktemp).applescript"
cat > "$tmp" <<APPLESCRIPT
-- Read a dropped/opened PDF (or the newest in Downloads) via aloud.
on readFile(posixPath)
	do shell script quoted form of "$PDFREAD" & " " & quoted form of posixPath & " >/dev/null 2>&1 &"
end readFile

on open theItems
	repeat with anItem in theItems
		readFile(POSIX path of anItem)
	end repeat
end open

on run
	-- launched with no file (Dock/Spotlight): pick one. Cancel just quits.
	try
		set theFile to choose file with prompt "Choose a PDF to read aloud" of type {"com.adobe.pdf"}
	on error number -128
		return
	end try
	readFile(POSIX path of theFile)
end run
APPLESCRIPT

rm -rf "$APP"
osacompile -o "$APP" "$tmp"
rm -f "$tmp"

# Give it the branded icon (icns built from mac/icon.png).
if command -v iconutil >/dev/null && [ -f "$REPO/mac/icon.png" ]; then
  set="$(mktemp -d)/icon.iconset"; mkdir -p "$set"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s"           "$REPO/mac/icon.png" --out "$set/icon_${s}x${s}.png"      >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$REPO/mac/icon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$set" -o /tmp/spititout.icns
  # osacompile names the icon droplet.icns (an `on open` handler makes this a
  # droplet) or applet.icns; overwrite whichever exist so the icon actually shows.
  for name in droplet applet; do
    [ -f "$APP/Contents/Resources/$name.icns" ] && cp /tmp/spititout.icns "$APP/Contents/Resources/$name.icns"
  done
  touch "$APP"
  command -v lsregister >/dev/null && lsregister -f "$APP" 2>/dev/null || \
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
fi

echo "Built: $APP"
echo "Drag it to your Dock. Then drop a PDF on it, or right-click a PDF ▸ Open With ▸ Spit It Out."
