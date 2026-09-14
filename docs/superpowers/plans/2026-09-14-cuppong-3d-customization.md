# CupPong 3D Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 컵퐁을 실제 3D로 바꾸고 컵별 사진을 저장·적용하며 예상 궤적을 제거한다.

**Architecture:** 순수 규칙 `CupPong`은 그대로 두고 `CupPongScene`이 규칙 좌표를 RealityKit 엔티티로 표현한다. `CupPongCustomizationStore`가 정규화된 사진의 디스크 저장을, `CupPongCustomizationView`가 PhotosPicker와 편집·미리보기를 맡는다. 화면은 실제 공 재생 상태만 씬에 전달한다.

**Tech Stack:** Swift 6, SwiftUI, RealityKit, PhotosUI, ImageIO, Swift Testing, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-14-cuppong-3d-customization.md`

## Global Constraints

- iOS 18+, Swift 6 strict concurrency. 외부 패키지를 추가하지 않는다.
- 예상 경로·착지점·정답을 알려 주는 조준 표시는 그리지 않는다.
- 변경은 `cuppong-3d` (별도 Orca 작업 폴더)에서 수행하고 배포는 별도 요청 시 진행한다.

### Task 1: 사진 저장과 정규화

**Files:** Create `App/Games/CupPong/CupPongCustomizationStore.swift`, `Tests/YachtDiceTests/CupPongCustomizationTests.swift`.

**Interfaces:** `@MainActor @Observable final class CupPongCustomizationStore`, `init(directory: URL)`, `func image(for cup: Int) -> UIImage?`, `func setImage(data: Data, for cup: Int) throws`, `func removeImage(for cup: Int) throws`, `var revision: Int`.

- [x] 실패 테스트: 임시 폴더에 가로로 긴 이미지를 넣고 새 store에서 다시 읽어 512×512인지, 다른 컵은 nil인지 확인한다. 잘못된 데이터가 기존 이미지를 덮지 않는지, 삭제가 재실행 뒤에도 유지되는지 확인한다.
```swift
try store.setImage(data: photo, for: 3)
#expect(CupPongCustomizationStore(directory: folder).image(for: 3)?.size == CGSize(width: 512, height: 512))
#expect(store.image(for: 2) == nil)
```
- [x] 새 타입 없음으로 실패하는 것을 확인한다. ImageIO thumbnail(transform=true, maxPixelSize=1024)에서 정사각형 512px JPEG를 생성하고 `.atomic`으로 저장한 뒤 캐시와 revision을 갱신한다.
- [x] 단위 테스트로 저장·삭제·오류·번호 범위 처리를 확인한다.

### Task 2: 실제 3D 테이블과 컵

**Files:** Create `App/Games/CupPong/CupPongScene.swift`, `Tests/YachtDiceTests/CupPongSceneTests.swift`; replace `App/Games/CupPong/CupPongTableView.swift`.

**Interfaces:** `@MainActor final class CupPongScene`, `let root: Entity`, `let camera: Entity`, `func update(cups: [Bool], ball: (x: Int, y: Int, height: CGFloat)?, vanishing: Int?, customization: CupPongCustomizationStore)`, `static func position(x: Int, y: Int) -> SIMD3<Float>`.

- [x] 실패 테스트: 열 개 컵의 위치가 규칙 좌표에서 변환되며 비워진 컵만 숨고 실제 공이 착지점으로 이동하는지 확인한다.
```swift
var cups = Array(repeating: true, count: 10)
cups[4] = false
scene.update(cups: cups, ball: (200, 2400, 0), vanishing: nil, customization: store)
#expect(scene.root.findEntity(named: "cup.4")?.isEnabled == false)
#expect(scene.root.findEntity(named: "cup.3")?.isEnabled == true)
```
- [x] 실패를 확인한 뒤 원뿔대 곡면 MeshDescriptor로 컵 외벽·내벽·테두리를 만들고 PBR 재질을 입힌다. 전면 곡면 패치에 컵별 사진을 입히며 revision이 바뀔 때만 텍스처를 교체한다.
- [x] `RealityView`에 root와 camera를 넣고 update에서 컵·공을 갱신한다. 카메라는 세로 화면에서 테이블과 컵을 모두 보여 준다.
- [x] 씬 테스트와 시뮬레이터 스크린샷으로 컵 구멍·사진·공·테이블 구도를 확인한다.

### Task 3: 편집 화면과 궤적 제거

**Files:** Create `App/Games/CupPong/CupPongCustomizationView.swift`; modify `CupPongMenu.swift`, `CupPongScreen.swift`, `Tests/YachtDiceUITests/CupPongUITests.swift`, `README.md` and 컵퐁 스펙.

**Interfaces:** `CupPongCustomizationView(store:)`; 메뉴의 `menu.cuppong.customize`, 컵 선택 `cuppong.customize.cup.N`, 사진 선택·삭제·완료 액션. 기본 store는 앱 지원 폴더를 사용한다.

- [x] UI 테스트에서 메뉴의 커스텀 버튼과 컵 10개 선택·완료·게임 진입을 확인한다. 새 버튼이 없어 실패하는 것을 확인한다.
- [x] 사진 선택은 `PhotosPicker(selection:matching: .images)`와 `loadTransferable(type: Data.self)`를 쓴다. 불러오는 중 선택 대상을 잠그고 실패는 alert로 보인다. 선택 번호와 async 작업 수명을 고정해 다른 컵에 사진이 들어가지 않게 한다.
- [x] `CupPongScreen`의 `aim`과 드래그 중 landing 계산을 제거한다. 드래그 속도 표본과 놓을 때 shot 계산은 유지한다. 실제 ball 재생만 씬으로 전달한다.
- [x] 컵퐁 UI, 전체 앱 단위와 GameCore 테스트를 실행한다. 스크린샷으로 기본 3D·커스텀 3D를 확인하고 README와 스펙의 점선 설명을 갱신한다.


### Task 4: 온라인 사진 공유 (사용자 확정)

**Files:** `App/Online/CupPongPhotoService.swift`, `supabase/migrations/20260914161000_cuppong_designs.sql`, `Tests/YachtDiceTests/CupPongPhotoE2ETests.swift`, `App/YachtDiceApp.swift`.

**Interfaces:** `CupPongPhotoService(service:)`, `publish(_ store:) async throws`, `fetch(owner:) async throws -> Design?`, `revision(owner:) async throws -> UUID?`, `load(_ design:) throws -> CupPongCustomizationStore`.

- [x] 서로 다른 계정으로 사진 업로드 → 방 입장 → 상대 읽기 → 사진 삭제를 시험한다. 방에 들어오기 전 계정과 제삼자는 읽지 못하고 타인 uid로 upsert하면 거부되는지 검사한다.
- [x] 사진 묶음은 `{owner_uid, images: {"0": "base64 JPEG"}, revision}`으로 전달한다. 번호 0~9, JSON 객체, 사진당 350KB 이하의 base64 JPEG를 SQL 제약으로 검사한다. 소유자만 INSERT/UPDATE/DELETE하며 실제 컵퐁 매치 참가자만 상대 행을 읽는다.
- [x] `SupabaseService`를 화면·편집기로 전달하고 사진 변경 시 publish한다. 화면은 온라인에서 목표 컵의 소유자를 따르고 10초마다 상대 revision을 조회한다. 실패 상태를 표시하며 사진 다운로드 완료 전에는 기본 3D 컵으로 플레이할 수 있다.
- [x] 추가 마이그레이션을 기존 서버에 적용하고 실제 서비스 통합 테스트를 실행한다. 앱 배포는 이 작업 범위에 포함하지 않는다.


## 검증 기록 (2026-09-14)

- 전체 앱 단위: 178개 통과 (이후 사용하지 않는 2D 원근 테스트 1개 제거).
- 최종 컵퐁 단위: 사진 저장·실패·씬 반영·입력·공 재생 7개 통과.
- 컵퐁 UI: 편집 진입·컵 선택·종료, 로컬 던지기 2개 통과.
- GameCore: 32개 통과.
- 실제 Supabase: `CupPongPhotoE2ETests` 1개 통과. 상대에게 전달·제삼자 읽기 차단·덮어쓰기 차단·삭제 반영 확인.
- 마이그레이션 적용 및 `supabase_migrations.schema_migrations` 기록 완료.
- 전용 `CupPong Dev` 시뮬레이터에서 PhotosPicker로 만든 테스트 이미지를 선택해 올바른 방향의 곡면 매핑과 온라인 공유 완료를 확인했다.
- 다른 에이전트의 알까기 작업과 분리한 `/Users/leejungheon/orca/workspaces/yacht_dice_proj/cuppong-3d`에서 작업했다. 앱 배포는 수행하지 않았다.
