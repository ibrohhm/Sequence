#!/bin/sh
# Builds Sequence.app (unsigned, personal use) from the SwiftPM executable; no Xcode needed.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Sequence.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/SequenceApp" "$APP/Contents/MacOS/Sequence"
cp App/Resources/plantuml.jar App/Resources/PLANTUML_VERSION App/Resources/marked.min.js App/Resources/AppIcon.icns "$APP/Contents/Resources/"
# Self-contained Java runtime (jlink'd from the installed JDK), so the app needs no Java on the target Mac.
JRE=build/jre
if [ ! -x "$JRE/bin/java" ]; then
    JLINK="$(/usr/libexec/java_home 2>/dev/null)/bin/jlink"
    [ -x "$JLINK" ] || JLINK="$(ls /opt/homebrew/opt/openjdk/bin/jlink /usr/local/opt/openjdk/bin/jlink 2>/dev/null | head -1)"
    [ -x "$JLINK" ] || { echo "jlink not found: install a JDK (brew install openjdk) to bundle Java" >&2; exit 1; }
    rm -rf "$JRE"
    "$JLINK" --add-modules java.base,java.desktop,java.logging,java.prefs,java.scripting,java.xml,jdk.unsupported \
        --strip-debug --no-header-files --no-man-pages --compress=zip-6 --output "$JRE"
fi
cp -R "$JRE" "$APP/Contents/Resources/jre"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Sequence</string>
<key>CFBundleIdentifier</key><string>local.plantuml-studio</string>
<key>CFBundleExecutable</key><string>Sequence</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed" >&2
echo "$APP"
