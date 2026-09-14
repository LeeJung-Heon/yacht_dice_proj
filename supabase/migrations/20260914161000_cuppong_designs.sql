-- 컵 사진은 512px JPEG 열 장을 한 번에 교체한다. 대전 로그·방송에는 사진을 넣지 않는다.
create function public.cuppong_images_valid(images jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare entry record; bytes bytea;
begin
  if jsonb_typeof(images) <> 'object' or pg_column_size(images) > 3000000 then return false; end if;
  for entry in select * from jsonb_each(images) loop
    if entry.key !~ '^[0-9]$' or jsonb_typeof(entry.value) <> 'string'
       or length(entry.value #>> '{}') > 350000 then return false; end if;
    begin
      bytes := decode(entry.value #>> '{}', 'base64');
      if length(bytes) < 4 or substring(bytes from 1 for 2) <> decode('ffd8', 'hex') then return false; end if;
    exception when others then return false;
    end;
  end loop;
  return true;
end;
$$;

create table public.cuppong_designs (
  owner_uid uuid primary key references auth.users(id) on delete cascade,
  images jsonb not null default '{}'::jsonb check (public.cuppong_images_valid(images)),
  revision uuid not null default gen_random_uuid()
);
alter table public.cuppong_designs enable row level security;
revoke all on public.cuppong_designs from anon;
grant select, insert, update, delete on public.cuppong_designs to authenticated;

create policy cuppong_designs_read on public.cuppong_designs for select to authenticated using (
  owner_uid = (select auth.uid()) or exists (
    select 1 from public.matches m
    where m.game = 'cuppong'
      and (select auth.uid()) in (m.host_uid, m.guest_uid)
      and cuppong_designs.owner_uid in (m.host_uid, m.guest_uid)
  )
);
create policy cuppong_designs_insert on public.cuppong_designs for insert to authenticated
  with check (owner_uid = (select auth.uid()));
create policy cuppong_designs_update on public.cuppong_designs for update to authenticated
  using (owner_uid = (select auth.uid())) with check (owner_uid = (select auth.uid()));
create policy cuppong_designs_delete on public.cuppong_designs for delete to authenticated
  using (owner_uid = (select auth.uid()));
