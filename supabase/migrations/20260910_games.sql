-- P7: 여러 게임과 Game Center 신원, 승자 기록
alter table public.matches
  add column if not exists game text not null default 'yacht',
  add column if not exists host_player text,
  add column if not exists guest_player text,
  add column if not exists winner_seat smallint;
alter table public.matches drop constraint if exists matches_game_check;
alter table public.matches add constraint matches_game_check
  check (game in ('yacht', 'omok', 'cuppong', 'alkkagi'));
alter table public.matches drop constraint if exists matches_winner_seat_check;
alter table public.matches add constraint matches_winner_seat_check check (winner_seat is null or winner_seat in (0, 1));
create index if not exists matches_host_player_idx on public.matches (host_player) where host_player is not null;
create index if not exists matches_guest_player_idx on public.matches (guest_player) where guest_player is not null;

-- 게스트가 gamePlayerID를 함께 넣는다
drop function if exists public.join_match(text, text);
create or replace function public.join_match(p_code text, p_name text, p_player text default null)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  m public.matches;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  if p_name is null or char_length(p_name) not between 1 and 20 then
    raise exception 'invalid name';
  end if;
  update public.matches
     set guest_uid = uid, guest_name = p_name, guest_player = p_player, status = 'playing'
   where code = p_code and status = 'waiting' and guest_uid is null and host_uid <> uid
   returning * into m;
  if m.id is null then
    raise exception 'room not found';
  end if;
  return m;
end;
$$;
revoke execute on function public.join_match(text, text, text) from public, anon;
grant execute on function public.join_match(text, text, text) to authenticated;

-- 좌석·게임·플레이어는 고정이고 끝난 판은 바뀌지 않는다
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
  if old.status = 'finished' then
    raise exception 'match is finished';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Game Center 신원 ↔ 익명 uid
create table if not exists public.profiles (
  player text primary key,
  uid uuid not null references auth.users (id) on delete cascade,
  name text not null,
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select to authenticated using (true);
drop policy if exists "profiles insert own" on public.profiles;
create policy "profiles insert own" on public.profiles for insert to authenticated with check (uid = (select auth.uid()));
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update to authenticated
  using (uid = (select auth.uid())) with check (uid = (select auth.uid()));

-- 앱을 지웠다 깔면 익명 uid가 바뀌므로, 같은 gamePlayerID 행을 새 uid로 다시 잇는다.
create or replace function public.link_profile(p_player text, p_name text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  row public.profiles;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  if p_player is null or char_length(p_player) not between 1 and 200 then
    raise exception 'invalid player';
  end if;
  if p_name is null or char_length(p_name) not between 1 and 40 then
    raise exception 'invalid name';
  end if;
  insert into public.profiles (player, uid, name, updated_at)
  values (p_player, uid, p_name, now())
  on conflict (player) do update set uid = excluded.uid, name = excluded.name, updated_at = now()
  returning * into row;
  return row;
end;
$$;
revoke execute on function public.link_profile(text, text) from public, anon;
grant execute on function public.link_profile(text, text) to authenticated;

-- 전적. Game Center 사용자는 gamePlayerID로, 미로그인은 uid로 센다. security_invoker라 내 매치만 보인다.
create or replace view public.records with (security_invoker = true) as
with seats as (
  select game, coalesce(host_player, host_uid::text) as player, 0 as seat, winner_seat from public.matches where status = 'finished'
  union all
  select game, coalesce(guest_player, guest_uid::text), 1, winner_seat from public.matches where status = 'finished' and guest_uid is not null
)
select player, game,
       count(*) filter (where winner_seat = seat) as wins,
       count(*) filter (where winner_seat is not null and winner_seat <> seat) as losses,
       count(*) filter (where winner_seat is null) as draws
from seats group by player, game;
grant select on public.records to authenticated;
