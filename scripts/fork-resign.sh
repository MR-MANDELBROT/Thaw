#!/bin/zsh
# Re-sign an unsigned (CI) Thaw.app with one Developer ID, inside-out.
# Usage: fork-resign.sh /path/to/Thaw.app ["Developer ID Application: Maximilian Marquart (S3725YB7V6)"] [GROUP]
set -euo pipefail
APP=${1:?app path}
ID=${2:-"Developer ID Application: Maximilian Marquart (S3725YB7V6)"}
GROUP=${3:-S3725YB7V6.com.stonerl.Thaw}
TS=--timestamp; [[ $ID == - ]] && TS=--timestamp=none
C="$APP/Contents"
tmp=$(mktemp -d)
cat > "$tmp/app.plist" <<P
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
<key>com.apple.security.files.user-selected.read-only</key><true/>
</dict></plist>
P
cat > "$tmp/appex.plist" <<P
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
P
# Compiled suite name must equal the entitlement, or the controls channel silently dies.
for bin in "$C/MacOS/Thaw" "$C/PlugIns/ThawControls.appex/Contents/MacOS/ThawControls"; do
  [[ -f $bin ]] || continue
  strings -a "$bin" | grep -F -- "$GROUP" >/dev/null || { echo "error: $bin does not contain $GROUP" >&2; exit 1; }
done
xattr -cr "$APP"
sign() { codesign --force --sign "$ID" --options runtime $TS "$@"; }
S="$C/Frameworks/Sparkle.framework/Versions/B"
if [[ -d $S ]]; then
  sign "$S/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$S/XPCServices/Downloader.xpc"
  sign "$S/Autoupdate"
  sign "$S/Updater.app"
  sign "$C/Frameworks/Sparkle.framework"
fi
for f in "$C"/Frameworks/*.framework(N) "$C"/Frameworks/*.dylib(N); do [[ $f == */Sparkle.framework ]] || sign "$f"; done
for x in "$C"/XPCServices/*.xpc(N); do
  for f in "$x"/Contents/Frameworks/*.framework(N) "$x"/Contents/Frameworks/*.dylib(N); do sign "$f"; done
  sign "$x"
done
for h in "$C"/Helpers/*(N.x); do sign --identifier "$(basename "$h")" "$h"; done
for e in "$C"/Library/Extras/*.app(N); do sign "$e"; done
for p in "$C"/PlugIns/*.appex(N); do sign --entitlements "$tmp/appex.plist" "$p"; done
sign --entitlements "$tmp/app.plist" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
rm -rf "$tmp"
