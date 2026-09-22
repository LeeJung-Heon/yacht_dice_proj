#!/bin/zsh
# App Store Connect API 키를 찾아 ASC_KEY_PATH·ASC_KEY_ID·ASC_ISSUER_ID를 채운다. source 해서 쓴다.
#
# 키 파일은 git이 무시하는 Tools/Release/keys/AuthKey_<KEY_ID>.p8 에 둔다. 파일이 하나면 그것을 쓰고,
# 이미 환경 변수로 준 값은 건드리지 않는다. Issuer ID는 팀마다 하나라 여기에 적어 둔다.
#
#   source Tools/Release/env.sh
#   swift Tools/Release/asc.swift get /v1/apps
#
# 호출한 셸의 글롭 옵션에 기대지 않도록 함수 안에서 옵션을 고정한다.
_asc_env() {
  emulate -L zsh
  setopt null_glob
  local root="${1:A:h:h:h}"
  local -a keys
  keys=("$root"/Tools/Release/keys/AuthKey_*.p8)
  if [[ -z "${ASC_KEY_PATH:-}" && ${#keys} -eq 1 ]]; then
    export ASC_KEY_PATH="${keys[1]}"
    export ASC_KEY_ID="${ASC_KEY_ID:-${${keys[1]:t:r}#AuthKey_}}"
  elif [[ -z "${ASC_KEY_PATH:-}" && ${#keys} -gt 1 ]]; then
    echo "Tools/Release/keys/ 에 키가 여러 개다. ASC_KEY_PATH와 ASC_KEY_ID를 직접 준다." >&2
  fi
  export ASC_ISSUER_ID="${ASC_ISSUER_ID:-837de746-ac77-4806-801d-9765067971fa}"
}
_asc_env "${(%):-%x}"
unset -f _asc_env
