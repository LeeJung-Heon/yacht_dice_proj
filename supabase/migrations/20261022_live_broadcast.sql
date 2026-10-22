-- 참가자는 자기 판의 토픽에 Presence뿐 아니라 클라이언트 브로드캐스트(빠른 길 `move`, 순간 상태 `live`)도 보낼 수 있다
drop policy if exists "participants send presence" on realtime.messages;
drop policy if exists "participants send broadcast and presence" on realtime.messages;
create policy "participants send broadcast and presence" on realtime.messages
  for insert to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1 from public.matches m
      where 'match:' || m.id::text = (select realtime.topic())
        and (select auth.uid()) in (m.host_uid, m.guest_uid)));

-- 빠른 길로 수를 먼저 받은 상대가 그 위에 둔 로그를, 늦게 도착한 옛 갱신이 덮지 못하게 한다.
-- 같은 값은 통과시킨다 — join_match와 pg_cron처럼 로그를 건드리지 않는 갱신이 있다.
create or replace function public.matches_guard_event_count()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.event_count < old.event_count then
    raise exception 'event count must not decrease';
  end if;
  return new;
end;
$$;
drop trigger if exists matches_guard_event_count on public.matches;
create trigger matches_guard_event_count before update on public.matches
  for each row execute function public.matches_guard_event_count();

-- 트리거 함수는 RPC로 부를 이유가 없다
revoke execute on function public.matches_guard_event_count() from public, anon, authenticated;
