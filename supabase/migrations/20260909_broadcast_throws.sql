-- 힌트와 다음 차례 좌석
alter table public.matches
  add column if not exists throws jsonb not null default '[]'::jsonb,
  add column if not exists turn_seat smallint;
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check
  check (status in ('waiting', 'playing', 'finished', 'abandoned'));

-- 갱신을 비공개 채널 match:<id>로 브로드캐스트한다 (WAL을 거치지 않아 빠르다)
create or replace function public.matches_broadcast()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.broadcast_changes(
    'match:' || new.id::text, tg_op, tg_op, tg_table_name, tg_table_schema, new, old);
  return null;
end;
$$;
drop trigger if exists matches_broadcast on public.matches;
create trigger matches_broadcast
  after update on public.matches
  for each row execute function public.matches_broadcast();

-- 참가자만 그 토픽의 브로드캐스트·Presence를 받고, Presence를 보낼 수 있다
drop policy if exists "participants receive match broadcasts" on realtime.messages;
create policy "participants receive match broadcasts" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1 from public.matches m
      where 'match:' || m.id::text = (select realtime.topic())
        and (select auth.uid()) in (m.host_uid, m.guest_uid)));
drop policy if exists "participants send presence" on realtime.messages;
create policy "participants send presence" on realtime.messages
  for insert to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and exists (
      select 1 from public.matches m
      where 'match:' || m.id::text = (select realtime.topic())
        and (select auth.uid()) in (m.host_uid, m.guest_uid)));

-- 3일 넘게 멈춘 판은 버려진 것으로 본다
create or replace function public.mark_abandoned_matches()
returns integer
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update public.matches set status = 'abandoned'
    where status = 'playing' and updated_at < now() - interval '3 days'
    returning 1)
  select count(*)::integer from updated;
$$;
revoke execute on function public.mark_abandoned_matches() from public, anon, authenticated;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('mark-abandoned-matches', '*/10 * * * *', $$select public.mark_abandoned_matches()$$);

-- 트리거 함수는 RPC로 부를 이유가 없다
revoke execute on function public.matches_broadcast() from public, anon, authenticated;
