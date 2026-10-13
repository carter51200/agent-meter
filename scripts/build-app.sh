#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release --product AgentMeter --arch arm64 --arch x86_64
binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
app_dir="$project_dir/dist/Agent Meter.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/AgentMeter" "$app_dir/Contents/MacOS/AgentMeter"
swift "$project_dir/scripts/render-brand.swift" "$project_dir/Assets/codex-template.svg" "$project_dir/Assets/codex-template.png"
for resource in codex-template.png claude.png antigravity-template.png; do
    cp "$project_dir/Assets/$resource" "$app_dir/Contents/Resources/"
done
# Remove obsolete resources from earlier local builds.
rm -f "$app_dir/Contents/Resources/codex.png" "$app_dir/Contents/Resources/codex-dark.png" "$app_dir/Contents/Resources/antigravity.png"
cp "$project_dir/Assets/CodexBar-LICENSE.txt" "$app_dir/Contents/Resources/"
swift "$project_dir/scripts/make-icon.swift" "$project_dir/.build"
iconutil -c icns "$project_dir/.build/AgentMeter.iconset" -o "$app_dir/Contents/Resources/AgentMeter.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AgentMeter</string>
<key>CFBundleIdentifier</key><string>com.carter.agentmeter</string>
<key>CFBundleName</key><string>Agent Meter</string>
<key>CFBundleDisplayName</key><string>Agent Meter</string>
<key>CFBundleIconFile</key><string>AgentMeter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$project_dir/dist/Agent-Meter.zip"
printf '%s\n' "$app_dir"
