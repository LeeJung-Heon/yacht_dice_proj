# Yacht Dice — P6: 온라인 대전 실시간 고도화 설계

- 작성일: 2026-09-09
- 상태: 구현 완료 (2026-09-09). 통합 테스트로 지연 중앙값 0.1초 안팎, 권한·Presence·자세 재현을 확인했고 푸시는 실기기 확인이 남았다
- 선행: P5 Supabase 방 코드 온라인 (`2026-09-07-yacht-dice-p5-supabase-online-design.md`)
- 범위: 전달 지연과 재현(A), 가용성과 푸시 알림(B). 서버 주사위와 자동 매칭(C)은 다음 스펙이다.

## 1. 목표

지금은 이벤트마다 행을 갱신하고 상대가 WAL 기반 Postgres Changes로 받아 200~500ms가 걸리며, 끊기면 3초 폴링이 받치고, 상대 화면의 던지기 궤적은 기기마다 다르게 고르며, 앱이 닫힌 상대에게는 알림이 없다. 이 스펙은 전달을 50~150ms로 줄이고 두 화면이 같은 던지기를 보게 하며 상대의 접속 상태와 연결 상태를 보여 주고, 앱이 닫힌 상대에게 "내 차례" 푸시를 보내고 버려진 판을 정리한다.

## 2. 결정

| 항목 | 결정 |
|---|---|
| 전달 | DB 트리거에서 `realtime.broadcast_changes`로 비공개 채널 `match:<id>`에 쏜다. Postgres Changes 구독은 없애고 3초 폴링은 그대로 둔다 |
| 권한 | `realtime.messages`에 참가자만 그 토픽을 받도록 SELECT 정책을 둔다 |
| 재현 | 굴린 쪽이 궤적 ID·방향·회전 선택 5개를 `throws` 열에 이벤트 번호와 함께 적고, 받는 쪽은 같은 값으로 재생한다 |
| 접속 상태 | 같은 채널의 Presence로 상대의 접속·관전을 표시하고, 채널 상태로 연결 끊김을 표시한다 |
| 푸시 | APNs 토큰을 `device_tokens`에 두고, 차례가 바뀌면 웹훅이 Edge Function `notify-turn`을 불러 상대 기기에 보낸다 |
| 정리 | `pg_cron`이 3일 넘게 멈춘 판을 `abandoned`로 바꾼다 |
| 측정 | 통합 테스트가 호스트 기록 → 게스트 화면까지의 지연을 재고 1.5초 아래를 강제한다 |

## 3. 서버

### 3.1 Broadcast from Database

`matches`에 `throws jsonb not null default '[]'`와 `turn_seat smallint`를 더한다. `AFTER UPDATE` 트리거 `matches_broadcast`가 `realtime.broadcast_changes('match:' || new.id, TG_OP, TG_OP, TG_TABLE_NAME, TG_TABLE_SCHEMA, new, old)`를 부르며 비공개로 보낸다. `realtime.messages`에 정책을 둔다.

```sql
create policy "participants receive match broadcasts" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1 from public.matches m
      where 'match:' || m.id::text = (select realtime.topic())
        and (select auth.uid()) in (m.host_uid, m.guest_uid)));
create policy "participants send presence" on realtime.messages
  for insert to authenticated
  with check (realtime.messages.extension = 'presence' and exists (같은 조건));
```

클라이언트는 구독 전에 `realtimeV2.setAuth(세션 토큰)`을 부르고 `isPrivate = true`로 채널을 연다. 브로드캐스트 페이로드의 `record`가 행 전체라 `MatchRow`로 그대로 디코드한다.

### 3.2 던지기 힌트

`throws`는 `[{ "event": 이벤트 번호, "trajectory": 궤적 ID, "direction": 0|1|2, "yaws": [0..3 × 5] }]`이며 굴린 쪽이 `publishProgress`에 함께 올린다. 받는 쪽은 `rolled` 이벤트를 재생할 때 같은 번호의 힌트가 있으면 그 궤적과 회전 선택으로 재생하고, 없으면 지금처럼 고른다. 힌트는 연출일 뿐이라 검증하지 않고, 없는 궤적 ID면 무시한다.

### 3.3 푸시

- `device_tokens(uid uuid, token text primary key, platform text default 'ios', updated_at)`이며 RLS는 자기 행만 쓰고 읽게 한다.
- 클라이언트는 온라인 메뉴에 들어올 때 알림 권한을 묻고 APNs 토큰을 받아 upsert한다.
- 클라이언트는 `endTurn`·`endMatch`에서 `turn_seat`(다음 차례 좌석, 끝나면 null)를 함께 갱신한다.
- 트리거 `matches_turn_webhook`는 `turn_seat`가 바뀌거나 `guest_uid`가 채워질 때 `pg_net`의 `net.http_post`로 Edge Function `notify-turn`을 부르며, 비밀 헤더 `X-Webhook-Secret`은 Vault의 `webhook_secret`에서 읽는다.
- `notify-turn`은 행에서 알릴 좌석의 uid를 고르고(차례가 바뀌면 그 좌석, 게스트 입장이면 호스트) `device_tokens`에서 토큰을 읽어 APNs(`api.push.apple.com`, HTTP/2, ES256 JWT)로 `{"aps":{"alert":{"title":"내 차례","body":"<상대>이(가) 두었다"},"sound":"default"},"matchID":"<id>"}`를 보낸다. 키는 Supabase 시크릿 `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`다. 410/400 `BadDeviceToken`이면 토큰을 지운다.
- 앱은 알림을 탭하면 `matchID`로 행을 읽어 `openSupabaseMatch`로 연다.

### 3.4 정리

`pg_cron`이 10분마다 `status = 'playing' and updated_at < now() - interval '3 days'`인 행을 `abandoned`로 바꾸고, 목록에서는 "상대가 떠남"으로 보여 지울 수 있게 한다. `abandoned`는 `status` 제약에 더한다.

### 3.5 사용자 작업

- 개발자 포털 Keys에서 APNs 키를 만들어 `.p8`, Key ID를 준다 (팀 ID는 `9P8KX3RJRR`).
- 앱 ID에 Push Notifications 기능은 Xcode 자동 서명이 켠다.

## 4. 앱

### 4.1 파일

| 파일 | 책임 |
|---|---|
| `App/Online/TurnTransport.swift` | `RemoteUpdate { log, throws }`를 흘리고 `publishProgress(log:throw:)`를 받는다. `presence`와 `connectionState` 스트림을 더한다 |
| `App/Online/SupabaseTurnTransport.swift` | 비공개 채널 브로드캐스트 구독, Presence 추적, 채널 상태, `throws`·`turn_seat` 갱신 |
| `App/Online/ThrowHint.swift` | 힌트 모델과 인코딩 |
| `App/Scene3D/DiceStage.swift` | `roll(... trajectoryID:yawChoices:)`로 지정 재생, 고른 값을 돌려준다 |
| `App/Game/GameSession.swift` | 굴림마다 힌트를 만들어 올리고, 원격 재생에 힌트를 쓰며, 상대 접속·연결 상태를 노출한다 |
| `App/Online/PushRegistration.swift` | 알림 권한, APNs 토큰 upsert, 알림 탭 처리 |
| `App/Views/PlayerStrip.swift`, `GameScreen.swift` | 접속 점과 "연결 끊김 — 재연결 중" 띠 |
| `supabase/functions/notify-turn/index.ts` | APNs 전송 |
| `supabase/migrations/*.sql` | 3.1~3.4 |

### 4.2 흐름

1. 게임을 열면 `SupabaseTurnTransport`가 세션 토큰으로 `match:<id>` 비공개 채널을 열고 `broadcastStream(event: "UPDATE")`와 `presenceChange()`를 구독하며 자기 상태 `{uid, name}`를 track한다.
2. 내가 굴리면 `DiceStage.roll`이 고른 궤적 ID·방향·회전 선택을 돌려주고, `GameSession`이 로그와 힌트를 함께 올린다.
3. 상대는 브로드캐스트 `record`를 디코드해 새 이벤트를 재생하며, `rolled`에는 힌트를 써서 같은 궤적을 보여 준다. 폴링은 3초마다 같은 행을 읽어 놓친 것을 채운다.
4. 채널이 `subscribed`가 아닌 상태가 3초 이상 이어지면 헤더 아래에 "연결 끊김 — 재연결 중"을 띄우고, 돌아오면 `refresh()`로 따라잡는다.
5. 내 턴이 끝나면 `turn_seat`를 상대 좌석으로 갱신하고, 트리거 → 웹훅 → Edge Function → APNs로 상대에게 "내 차례" 푸시가 간다. 상대가 알림을 탭하면 그 판이 열린다.

## 5. 테스트

| 대상 | 테스트 |
|---|---|
| 지연 | 통합: 호스트 `commit` 시각부터 게스트 `isLocalTurn`까지 중앙값을 재고 1.5초 아래, Realtime을 끈 폴링만으로는 5초 아래 |
| 권한 | 통합: 참가자가 아닌 익명 계정은 `match:<id>` 채널 구독이 실패한다 |
| 재현 | 통합: 게스트가 재생한 주사위 자세(`stage.orientation`)가 호스트와 같다 |
| 힌트 | 단위: 힌트 인코딩 왕복, 없는 궤적 ID는 무시하고 무작위로 재생 |
| Presence | 통합: 게스트가 채널에 들어오면 호스트의 `opponentPresent`가 참이 된다 |
| 푸시 | 단위: Edge Function의 APNs JWT 생성기를 `deno test`로 검증. 실제 전송은 실기기로 확인 |
| 정리 | 서버: `abandoned` 전환 함수를 SQL로 검증 |

## 6. 치르는 값

- 브로드캐스트는 3일 뒤 지워지는 `realtime.messages`에 쌓이며 무료 티어 한도 안이다.
- 힌트로 두 화면이 같은 궤적을 보지만 각자의 리드인 시작 자세는 다를 수 있다.
- 푸시는 사용자가 알림을 허용해야 하고, 실기기와 유료 계정이 있어야 검증할 수 있다.
