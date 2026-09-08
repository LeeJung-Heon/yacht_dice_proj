#!/bin/zsh
# TestFlight 업로드. 아카이브 → App Store Connect 업로드까지 한 번에 한다.
#
# 인증은 둘 중 하나다.
#   1) Xcode → Settings → Accounts에 팀의 Apple ID가 로그인돼 있다.
#        DEVELOPMENT_TEAM=9P8KX3RJRR Tools/Release/upload.sh
#   2) App Store Connect API 키 (Users and Access → Integrations → Team Keys, 역할 App Manager).
#      .p8 파일은 한 번만 내려받을 수 있다.
#        DEVELOPMENT_TEAM=9P8KX3RJRR ASC_KEY_PATH=~/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=... Tools/Release/upload.sh
#
# 업로드 뒤 App Store Connect의 TestFlight 탭에서 빌드 처리가 끝나기를 기다린 뒤 테스터 그룹에 붙인다.
set -uo pipefail
cd "$(dirname "$0")/../.."
: "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM 환경 변수에 팀 ID를 넣는다}"
OUT="${TMPDIR:-/tmp}/yacht-release"
rm -rf "$OUT" && mkdir -p "$OUT"

AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  : "${ASC_KEY_ID:?ASC_KEY_ID가 필요하다}"; : "${ASC_ISSUER_ID:?ASC_ISSUER_ID가 필요하다}"
  AUTH=(-authenticationKeyPath "${ASC_KEY_PATH/#\~/$HOME}" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" xcodegen generate
xcodebuild -project YachtDice.xcodeproj -scheme YachtDice -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/YachtDice.xcarchive" \
  -derivedDataPath "$OUT/dd" -allowProvisioningUpdates "${AUTH[@]}" archive | tail -3
# 내보내기(배포 서명·업로드)는 클라우드 배포 인증서 권한이 필요한데 App Manager 키에는 없다.
# 키로 먼저 시도하고 실패하면 Xcode에 로그인된 계정으로 다시 한다.
if ! xcodebuild -exportArchive -archivePath "$OUT/YachtDice.xcarchive" \
  -exportOptionsPlist Tools/Release/ExportOptions.plist -exportPath "$OUT/export" \
  -allowProvisioningUpdates "${AUTH[@]}" | tail -5; then
  echo "API 키로 내보내기 실패 — Xcode 계정으로 다시 시도한다"
  rm -rf "$OUT/export"
  xcodebuild -exportArchive -archivePath "$OUT/YachtDice.xcarchive" \
    -exportOptionsPlist Tools/Release/ExportOptions.plist -exportPath "$OUT/export" \
    -allowProvisioningUpdates | tail -5
fi
echo "업로드했다. App Store Connect → TestFlight에서 처리 완료를 기다린다."
