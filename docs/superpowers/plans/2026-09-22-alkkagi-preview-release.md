# Alkkagi Limited Preview and Release Implementation Plan

> **For agentic workers:** Execute the bounded steps with supervised agents; each owner validates their own changes and the coordinator integrates and releases.

**Goal:** 알까기의 초기 이동만 짧게 안내하고, 사용자가 확정한 게임 개선을 병합·배포한다.

**Architecture:** GameCore의 실제 시뮬레이션 결과 중 초기 구간만 화면 계층에서 자른다. 충돌·정지·승패 규칙과 온라인 로그는 변경하지 않는다. 최종 앱은 규칙 버전 2 서버와 함께 배포한다.

**Tech Stack:** Swift 6, SwiftUI, XCTest/Swift Testing, Supabase, Xcode archive, TestFlight.

**Spec:** `docs/superpowers/specs/2026-09-22-realistic-games.md`

## Constraints

- iOS 18 이상, 기존 19줄 오목·17줄 알까기·컵퐁 디자인/물리와 사진 공유 유지.
- 알까기 조준 안내는 최대 2500 격자 단위, 초기 0.2초, 전체 이동 앞 1/3 이내로 제한한다. 첫 충돌/범퍼/낙하 이후 경로는 보이지 않는다. 점선 끝은 흐려진다.
- 사용자 승인: 2026-09-22 디자인과 규칙 확정. 기존 병합·배포 요청을 이어서 수행한다.

## 1. 제한된 조준 안내

Files: `App/Games/Alkkagi/AlkkagiGeometry.swift`, `AlkkagiBoardView.swift`, `AlkkagiScreen.swift`, `Tests/YachtDiceTests/AlkkagiGeometryTests.swift`.

Interface: `AlkkagiGeometry.preview(state:flick:) -> [Alkkagi.Point]`.

- [x] 기존 전체 미리보기에 대해 최대 거리, 약한 샷의 정지점 비공개, 충돌 뒤 반사 비공개를 검증하는 실패 테스트를 실행한다.
- [x] 실제 시뮬레이션에서 시간·거리·첫 사건으로 구간을 잘라 반환하고 점선을 흐리게 그린다.
- [x] `AlkkagiGeometryTests`와 기존 알까기 UI 테스트를 통과시키고 조준 상태의 실제 렌더를 확인한다.

Run: `xcodebuild -project YachtDice.xcodeproj -scheme YachtDice -destination id=63BF8F36-C5CC-4CFB-8C3A-C9A6E9B345BB -derivedDataPath /tmp/realistic-games-dd -collect-test-diagnostics never -only-testing:YachtDiceTests/AlkkagiGeometryTests -only-testing:YachtDiceUITests/AlkkagiUITests test`

## 2. 온라인 통합과 릴리스

Files: `supabase/migrations/20260922_game_rules_version.sql`, `Tests/YachtDiceTests/SupabaseE2ETests.swift`, `CupPongPhotoE2ETests.swift`, `project.yml`, `README.md`.

- [x] 기존 서버의 함수·마이그레이션 목록과 배포 인증을 확인한다. 과거 마이그레이션의 이름 형식 차이 때문에 전체 db push는 실행하지 않는다.
- [x] 이번 규칙 버전 SQL만 트랜잭션으로 적용하고 마이그레이션 이력을 기록한다.
- [x] 운영 E2E로 새 규칙의 생성·참가·턴·종료·사진 공유 및 구 규칙 참가 거부를 확인한다.
- [x] 빌드 번호를 증가시키고 기능/문서 변경을 커밋하여 main으로 병합·push한다.
- [ ] 팀 `9P8KX3RJRR`로 Release archive를 생성하고 TestFlight 업로드 후 처리 상태와 기존 테스트 그룹 연결을 확인한다. (아카이브 완료, 업로드 진행 중)
- [ ] 실제 적용된 커밋·서버 변경·빌드·테스트 결과와 남은 외부 심사 상태를 기록한다.

Run E2E: `TEST_RUNNER_YACHT_SUPABASE_E2E=1 xcodebuild -project YachtDice.xcodeproj -scheme YachtDice -destination id=63BF8F36-C5CC-4CFB-8C3A-C9A6E9B345BB -derivedDataPath /tmp/realistic-games-dd -collect-test-diagnostics never -only-testing:YachtDiceTests/SupabaseE2ETests -only-testing:YachtDiceTests/CupPongPhotoE2ETests test`

Release: `DEVELOPMENT_TEAM=9P8KX3RJRR Tools/Release/upload.sh` or equivalent separate archive/export commands retaining logs and existing release artifacts.
