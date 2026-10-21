#!/bin/bash
set -euo pipefail

SRC_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
APP="${1:-$SRC_DIR/Rapid Photo Downloader.app}"
BIN="RapidPhotoDownloader"

command -v swiftc >/dev/null 2>&1 || {
    echo "error: swiftc not found. Install the Xcode Command Line Tools:" >&2
    echo "       xcode-select --install" >&2
    exit 1
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling $BIN..."
swiftc -O -emit-executable \
    -o "$APP/Contents/MacOS/$BIN" \
    "$SRC_DIR/HEIFThumbnail.swift" \
    "$SRC_DIR/RapidPhotoDownloader.swift"

printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>RapidPhotoDownloader</string>
	<key>CFBundleIdentifier</key>
	<string>com.etrigan63.rapid-photo-downloader</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Rapid Photo Downloader</string>
	<key>CFBundleDisplayName</key>
	<string>Rapid Photo Downloader</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || \
    echo "warning: ad-hoc codesign failed; the app may still run locally" >&2

echo "Built $APP"