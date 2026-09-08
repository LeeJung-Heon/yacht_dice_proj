#!/bin/zsh
# TestFlight 업로드. 유료 개발자 계정의 팀 ID와 Xcode에 로그인된 Apple ID가 필요하다.
#
#   DEVELOPMENT_TEAM=ABCDE12345 Tools/Release/upload.sh
#
# 아카이브 → App Store Connect 업로드까지 한 번에 한다. 업로드 뒤 App Store Connect의
# TestFlight 탭에서 빌드가 처리되기를 기다린 뒤 테스터 그룹에 붙인다.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM 환경 변수에 팀 ID를 넣는다}"
OUT="${TMPDIR:-/tmp}/yacht-release"
rm -rf "$OUT" && mkdir -p "$OUT"

xcodegen generate
xcodebuild -project YachtDice.xcodeproj -scheme YachtDice -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/YachtDice.xcarchive" \
  -derivedDataPath "$OUT/dd" -allowProvisioningUpdates archive | tail -3
xcodebuild -exportArchive -archivePath "$OUT/YachtDice.xcarchive" \
  -exportOptionsPlist Tools/Release/ExportOptions.plist -exportPath "$OUT/export" \
  -allowProvisioningUpdates | tail -5
echo "업로드했다. App Store Connect → TestFlight에서 처리 완료를 기다린다."
