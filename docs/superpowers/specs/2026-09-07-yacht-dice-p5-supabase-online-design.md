# Yacht Dice — P5: Supabase 방 코드 온라인 대전 설계

- 작성일: 2026-09-07
- 상태: 구현 완료 (2026-09-07). 통합 테스트와 시뮬레이터 두 대 검증 통과
- 선행: P3 Game Center 온라인 (`2026-09-07-yacht-dice-p2-p3-design.md` §5)
- 범위: Game Center 없이 무료로 동작하는 온라인 대전. 전송 계층만 바꾸고 규칙·3D·세션은 그대로다.

## 1. 목표

Game Center는 유료 개발자 계정에서만 켤 수 있으므로, 무료 Apple ID로 설치한 실기기 두 대가 Supabase 무료 티어를 통해 한 판을 완주하게 한다. `GameSession`은 이미 `TurnTransport`만 알고 있으니 `SupabaseTurnTransport` 하나와 방 코드 매칭 화면을 더하면 되고, Game Center 코드는 유료 계정을 만든 뒤 다시 쓸 수 있도록 남긴다.

## 2. 결정

| 항목 | 결정 |
|---|---|
| 서버 | Supabase 프로젝트 `yacht-dice`(ref `lkernselwouldtuialjh`, 서울, 무료 티어) |
| 식별 | 익명 로그인(`signInAnonymously`)으로 기기마다 `auth.uid()` 하나. 닉네임은 기기에 저장한 문자열 |
| 매칭 | 6자리 방 코드. 호스트가 만들고 게스트가 입력한다. 자동 매칭과 친구 목록은 없다 |
| 데이터 | `public.matches` 행 하나 = 한 판. `log`는 `MatchLog` JSON 그대로 |
| 전달 | 굴림·고정·기록마다 행을 갱신하고 Realtime Postgres Changes로 그 행의 UPDATE를 구독하므로 상대 플레이가 이벤트 단위로 실시간에 보인다. 앱이 열려 있을 때만 받고 푸시 알림은 없다 |
| 신뢰 | 상대 로그는 `GameState.canApply`로 검증한다(P3과 같다). 좌석 교체는 트리거가 막는다 |
| 기존 GC | `App/Online`에 남기되 메뉴에서는 부르지 않는다 |

## 3. 서버

### 3.1 스키마 (`create_matches` 마이그레이션, 적용 완료)

`matches(id, code, host_uid, guest_uid, host_name, guest_name, log jsonb, event_count, status, totals, created_at, updated_at)`이며 `status`는 `waiting → playing → finished`다. RLS는 참가자(`auth.uid() in (host_uid, guest_uid)`)만 읽고 갱신하게 하고, 삽입은 자기 자신을 호스트로 두는 대기 방만 허용한다. 방에 들어가는 사람은 아직 참가자가 아니라 행을 읽을 수 없으므로 `join_match(code, name)`을 `security definer`로 두되 함수 안에서 `auth.uid()`를 확인하고 대기 중인 빈 자리에만 넣는다. `matches_guard_seats` 트리거가 좌석 변경을 막고 `updated_at`을 갱신하며, 테이블은 `supabase_realtime` 발행에 들어 있다.

### 3.2 사용자 작업

대시보드 → Authentication → Sign In / Providers에서 **Anonymous sign-ins**를 켜야 한다. MCP로는 바꿀 수 없다.

## 4. 앱

### 4.1 파일

| 파일 | 책임 |
|---|---|
| `App/Online/SupabaseConfig.swift` | 프로젝트 URL과 publishable 키(공개용 키라 코드에 둔다) |
| `App/Online/SupabaseService.swift` | 클라이언트 하나, 익명 로그인, 방 만들기·들어가기·내 매치 목록, 닉네임 저장 |
| `App/Online/SupabaseTurnTransport.swift` | `TurnTransport` 구현. `endTurn`은 행 UPDATE, `incomingLogs`는 Realtime UPDATE 구독 |
| `App/Online/MatchRow.swift` | 행 ↔ `MatchRecord` 변환과 좌석 배치(순수, 테스트 대상) |
| `App/Views/OnlineMenu.swift` | 닉네임, 방 만들기(코드 표시·대기), 코드 입력, 진행 중인 매치 |
| `App/AppContainer.swift` | `openOnlineMatch`를 그대로 쓴다. Supabase 매치도 `GameMode.online(matchID:)` |

### 4.2 흐름

1. 온라인 메뉴에 들어오면 익명 로그인한다. 실패하면 이유(대개 익명 로그인 미설정)를 보여준다.
2. 호스트는 방 만들기를 누르고 6자리 코드를 본다. 앱은 코드로 행을 삽입하고 그 행의 UPDATE를 구독하며, `guest_uid`가 채워지면 좌석 `[host, guest]`로 게임을 연다. 호스트가 좌석 0이라 바로 내 차례다.
3. 게스트는 코드를 입력하고 `join_match`를 호출한다. 돌아온 행으로 좌석 `[host, guest]`, 내 좌석 1로 게임을 열고 상대 차례를 기다린다.
4. 굴림·고정마다 `publishProgress`로, 기록 뒤에는 `endTurn`으로 `log`, `event_count`, `status`를 UPDATE한다. 상대는 Realtime으로 새 행을 받아 P3과 같은 `replay(remote:)`로 내가 모르는 이벤트만 재생하므로 턴 도중에도 굴림이 그대로 보인다.
5. 게임이 끝나면 `status = finished`, `totals`를 쓴다.
6. 진행 중인 매치 목록은 `status <> 'finished'`인 내 행이며, 열면 `matchData`로 이어한다. 호스트가 대기 중인 방을 열면 다시 코드를 보여준다.

### 4.3 코드 생성

6자리 숫자를 클라이언트가 만들고 삽입이 `unique` 위반이면 다시 만든다(최대 5회). 코드는 `waiting`인 동안만 의미가 있고 끝난 방의 코드는 재사용될 수 있다.

## 5. 테스트

| 대상 | 테스트 |
|---|---|
| `MatchRow` | 행 → 좌석 배치(내가 호스트/게스트), 행 → `MatchLog` 디코드, 손상 로그 거부, 코드 형식 |
| 통합 (선택, 네트워크) | 실제 프로젝트에 익명 계정 둘로 방 만들기 → 들어가기 → 턴 UPDATE → Realtime 수신. 환경 변수 `YACHT_SUPABASE_E2E=1`일 때만 돈다 |
| UI | 온라인 메뉴에 닉네임·방 만들기·코드 입력이 있고 식별자 `online.status`, `online.create`, `online.join`, `online.code`가 있다 |

## 6. 치르는 값

- 푸시 알림이 없어 상대가 앱을 열어야 턴이 전달되고, 앱이 뒤로 가 있으면 Realtime 연결이 끊겨 다시 열 때 최신 행을 한 번 읽는다.
- 익명 계정은 앱을 지우면 사라지므로 진행 중인 매치도 잃는다.
- 눈은 클라이언트가 굴린다(P3 §7.4와 같다).
