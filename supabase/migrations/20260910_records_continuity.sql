-- P7 보강: 앱을 지웠다 깔아도 전적이 이어지고, 클라이언트가 보낸 플레이어 문자열을 서버가 검증한다
--
-- 익명 uid는 앱을 지우면 새로 발급되므로 uid만 보는 SELECT 정책으로는 예전 매치가 통째로 안 보인다.
-- `profiles`가 gamePlayerID ↔ 지금 uid를 이어 두므로, 그 연결을 지나 내 gamePlayerID가 좌석에 적힌 행도
-- 읽게 한다. 쓰기(UPDATE·DELETE) 정책은 uid 그대로라 예전 uid의 행은 읽기 전용이다.
drop policy if exists "matches_select_linked_player" on public.matches;
create policy "matches_select_linked_player" on public.matches for select to authenticated
  using (exists (select 1 from public.profiles p
                 where p.uid = (select auth.uid())
                   and p.player in (public.matches.host_player, public.matches.guest_player)));
-- 정책마다 uid로 profiles를 뒤지므로 uid 인덱스를 둔다(기본 키는 player뿐이다).
create index if not exists profiles_uid_idx on public.profiles (uid);

-- 좌석의 플레이어 문자열은 클라이언트가 보내는 값이라 그대로 믿으면 남의 gamePlayerID를 적어
-- 남의 전적을 늘릴 수 있다. `profiles`에 그 uid로 이어진 플레이어일 때만 받는다.
create or replace function public.matches_guard_players()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.host_player is not null
     and not exists (select 1 from public.profiles p where p.player = new.host_player and p.uid = new.host_uid) then
    raise exception 'host player is not linked';
  end if;
  if new.guest_player is not null
     and not exists (select 1 from public.profiles p where p.player = new.guest_player and p.uid = new.guest_uid) then
    raise exception 'guest player is not linked';
  end if;
  return new;
end;
$$;
drop trigger if exists matches_guard_players on public.matches;
create trigger matches_guard_players before insert on public.matches
  for each row execute function public.matches_guard_players();

-- 좌석·게임·플레이어는 고정이고 끝난 판은 바뀌지 않으며, 새로 적히는 플레이어는 이어진 것이어야 한다.
-- UPDATE에서는 값이 새로 들어오거나 바뀔 때만 연결을 본다 — 이미 적힌 행을 그대로 두는 갱신까지 막으면
-- 그 사이 다른 기기에서 프로필을 다시 이어 uid가 옮겨간 사용자가 진행 중인 판을 못 두고,
-- `mark_abandoned_matches` 일괄 갱신도 그런 행 하나에 통째로 실패한다.
create or replace function public.matches_guard_seats()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.host_uid is distinct from old.host_uid then
    raise exception 'host seat is fixed';
  end if;
  if old.guest_uid is not null and new.guest_uid is distinct from old.guest_uid then
    raise exception 'guest seat is fixed';
  end if;
  if new.game is distinct from old.game then
    raise exception 'game is fixed';
  end if;
  if old.host_player is not null and new.host_player is distinct from old.host_player then
    raise exception 'host player is fixed';
  end if;
  if old.guest_player is not null and new.guest_player is distinct from old.guest_player then
    raise exception 'guest player is fixed';
  end if;
  if new.host_player is not null and new.host_player is distinct from old.host_player
     and not exists (select 1 from public.profiles p where p.player = new.host_player and p.uid = new.host_uid) then
    raise exception 'host player is not linked';
  end if;
  if new.guest_player is not null and new.guest_player is distinct from old.guest_player
     and not exists (select 1 from public.profiles p where p.player = new.guest_player and p.uid = new.guest_uid) then
    raise exception 'guest player is not linked';
  end if;
  if old.status = 'finished' then
    raise exception 'match is finished';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- 게스트의 gamePlayerID도 같은 검증을 지난다. security definer라 트리거 앞에서 먼저 막는다.
-- `profiles`에도 `uid` 열이 있어 변수 이름을 `uid`로 두면 그 안에서 어느 쪽인지 갈리지 않는다(42702).
create or replace function public.join_match(p_code text, p_name text, p_player text default null)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  m public.matches;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if p_name is null or char_length(p_name) not between 1 and 20 then
    raise exception 'invalid name';
  end if;
  if p_player is not null
     and not exists (select 1 from public.profiles p where p.player = p_player and p.uid = v_uid) then
    raise exception 'player is not linked';
  end if;
  update public.matches
     set guest_uid = v_uid, guest_name = p_name, guest_player = p_player, status = 'playing'
   where code = p_code and status = 'waiting' and guest_uid is null and host_uid <> v_uid
   returning * into m;
  if m.id is null then
    raise exception 'room not found';
  end if;
  return m;
end;
$$;
revoke execute on function public.join_match(text, text, text) from public, anon;
grant execute on function public.join_match(text, text, text) to authenticated;

-- winner_seat가 생기기 전에 끝난 요트 판은 총점만 남아 전부 무승부로 세어졌다. 총점이 갈리는 판에만
-- 승자를 채우고 진짜 동점은 null(무승부)로 둔다. 끝난 판의 갱신은 트리거가 막으므로 잠깐 내리고,
-- updated_at까지 지금으로 밀지 않도록 브로드캐스트도 함께 멈춘다.
alter table public.matches disable trigger matches_guard_seats;
alter table public.matches disable trigger matches_broadcast;
update public.matches
   set winner_seat = case when totals[1] > totals[2] then 0 else 1 end
 where status = 'finished' and winner_seat is null
   and totals is not null and array_length(totals, 1) = 2
   and totals[1] <> totals[2];
alter table public.matches enable trigger matches_broadcast;
alter table public.matches enable trigger matches_guard_seats;
