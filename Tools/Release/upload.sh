#!/bin/zsh
# TestFlight 업로드. 아카이브 → App Store Connect 업로드까지 한 번에 한다.
#
# 인증은 App Store Connect API 키(Users and Access → Integrations → Team Keys)로 한다.
# 역할이 Admin이면 아카이브 내보내기의 클라우드 서명까지 키만으로 되고, App Manager면 내보내기는
# Xcode → Settings → Accounts에 로그인된 팀 계정으로 되돌아간다. .p8 파일은 한 번만 내려받을 수 있다.
#
# 키는 git이 무시하는 Tools/Release/keys/AuthKey_<KEY_ID>.p8 에 두면 자동으로 찾는다(Tools/Release/env.sh).
#   DEVELOPMENT_TEAM=9P8KX3RJRR Tools/Release/upload.sh
# 다른 곳의 키를 쓰려면 ASC_KEY_PATH·ASC_KEY_ID·ASC_ISSUER_ID를 직접 준다.
#
# 업로드 뒤 App Store Connect의 TestFlight 탭에서 빌드 처리가 끝나기를 기다린 뒤 테스터 그룹에 붙인다.
set -uo pipefail
cd "$(dirname "$0")/../.."
source Tools/Release/env.sh
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
# 키로 먼저 시도하고 실패하면 Xcode에 로그인된 계정으로 다시 한다(Admin 키면 첫 시도에 끝난다).
if ! xcodebuild -exportArchive -archivePath "$OUT/YachtDice.xcarchive" \
  -exportOptionsPlist Tools/Release/ExportOptions.plist -exportPath "$OUT/export" \
  -allowProvisioningUpdates "${AUTH[@]}" | tail -5; then
  echo "API 키로 내보내기 실패 — Xcode 계정으로 다시 시도한다"
  rm -rf "$OUT/export"
  if ! xcodebuild -exportArchive -archivePath "$OUT/YachtDice.xcarchive" \
    -exportOptionsPlist Tools/Release/ExportOptions.plist -exportPath "$OUT/export" \
    -allowProvisioningUpdates | tail -5; then
    echo "내보내기 실패. Xcode → Settings → Accounts에서 팀 $DEVELOPMENT_TEAM 계정에 다시 로그인한 뒤 다시 실행한다." >&2
    exit 1
  fi
fi
echo "업로드했다. App Store Connect → TestFlight에서 처리 완료를 기다린다."
