-- 규칙 2: 오목 19줄, 컵퐁 충돌 물리, 알까기 3판 2선승.
-- 앱 배포 전에 적용한다. 운영 데이터의 기존 로그는 바꾸지 않는다.
-- 3인자 함수를 남기면 PostgREST의 기본 인자 해석이 모호해지므로 새 시그니처로 교체한다.
drop function if exists public.join_match(text, text, text);
create or replace function public.join_match(
  p_code text, p_name text, p_player text default null,
  p_rules_version integer default 1, p_game text default null
)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rules_version integer;
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

  -- 버전 확인과 자리 배정을 같은 행 잠금 안에서 처리해 검사 사이에 다른 게스트가 들어올 수 없다.
  select * into m from public.matches
   where code = p_code and status = 'waiting' and guest_uid is null and host_uid <> v_uid
   for update;
  if m.id is null then
    raise exception 'room not found';
  end if;
  if p_game is not null and p_game is distinct from m.game then
    raise exception 'game mismatch';
  end if;
  v_rules_version := case when m.game = 'yacht' then 1
                         else coalesce((m.log ->> 'rulesVersion')::integer, 1) end;
  if p_rules_version is distinct from v_rules_version then
    raise exception 'rules version mismatch';
  end if;
  update public.matches
     set guest_uid = v_uid, guest_name = p_name, guest_player = p_player, status = 'playing'
   where id = m.id
   returning * into m;
  return m;
end;
$$;
revoke execute on function public.join_match(text, text, text, integer, text) from public, anon;
grant execute on function public.join_match(text, text, text, integer, text) to authenticated;

-- 진행 중인 판의 버전을 덮어쓰면 기존 수가 새 규칙으로 해석된다. 버전은 방 생성 시에 고정한다.
create or replace function public.matches_guard_rules_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.game <> 'yacht'
     and coalesce(old.log ->> 'rulesVersion', '1') is distinct from coalesce(new.log ->> 'rulesVersion', '1') then
    raise exception 'rules version is fixed';
  end if;
  return new;
end;
$$;
drop trigger if exists matches_guard_rules_version on public.matches;
create trigger matches_guard_rules_version before update on public.matches
  for each row execute function public.matches_guard_rules_version();

notify pgrst, 'reload schema';
