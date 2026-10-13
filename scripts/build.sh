#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Still Tuner.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -module-cache-path "$PWD/build/ModuleCache" -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/StillTuner" -framework SwiftUI -framework AppKit -framework AVFoundation -framework AudioToolbox -framework CoreAudio
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StillTuner</string>
<key>CFBundleIdentifier</key><string>kr.blue.still-tuner</string>
<key>CFBundleName</key><string>Still Tuner</string>
<key>CFBundleDisplayName</key><string>Still Tuner</string>
<key>CFBundleIconFile</key><string>Still</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.2</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSMicrophoneUsageDescription</key><string>기타의 음정을 표시하기 위해 선택한 오디오 인터페이스 입력을 읽습니다. 오디오를 녹음하거나 전송하지 않습니다.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp assets/Still.icns "$APP/Contents/Resources/Still.icns"
./scripts/sign.sh "$APP"
echo "$APP"
