#!/bin/sh
# Builds PlantUMLStudio.app (unsigned, personal use) from the SwiftPM executable; no Xcode needed.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/PlantUMLStudio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/PlantUMLStudio" "$APP/Contents/MacOS/"
cp App/Resources/plantuml.jar App/Resources/PLANTUML_VERSION App/Resources/marked.min.js "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>PlantUML Studio</string>
<key>CFBundleIdentifier</key><string>local.plantuml-studio</string>
<key>CFBundleExecutable</key><string>PlantUMLStudio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "$APP"
