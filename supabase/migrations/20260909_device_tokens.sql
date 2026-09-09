-- P6: APNs 기기 토큰과 차례 웹훅. 웹훅 비밀은 Vault에 두고 Edge Function 시크릿 WEBHOOK_SECRET과 같은 값이어야 한다.
create extension if not exists pg_net with schema extensions;

create table if not exists public.device_tokens (
  uid uuid not null references auth.users (id) on delete cascade,
  token text primary key,
  platform text not null default 'ios',
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_uid_idx on public.device_tokens (uid);
alter table public.device_tokens enable row level security;
create policy "own tokens select" on public.device_tokens for select to authenticated using (uid = (select auth.uid()));
create policy "own tokens insert" on public.device_tokens for insert to authenticated with check (uid = (select auth.uid()));
create policy "own tokens update" on public.device_tokens for update to authenticated
  using (uid = (select auth.uid())) with check (uid = (select auth.uid()));
create policy "own tokens delete" on public.device_tokens for delete to authenticated using (uid = (select auth.uid()));

-- 차례가 바뀌거나 게스트가 들어오면 Edge Function notify-turn을 부른다.
create or replace function public.matches_turn_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  secret text;
begin
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'webhook_secret';
  if secret is null then
    return null;
  end if;
  perform net.http_post(
    url := 'https://lkernselwouldtuialjh.supabase.co/functions/v1/notify-turn',
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Webhook-Secret', secret),
    body := jsonb_build_object('type', tg_op, 'table', tg_table_name, 'record', to_jsonb(new), 'old_record', to_jsonb(old)),
    timeout_milliseconds := 5000);
  return null;
end;
$$;
revoke execute on function public.matches_turn_webhook() from public, anon, authenticated;

drop trigger if exists matches_turn_webhook on public.matches;
create trigger matches_turn_webhook
  after update on public.matches
  for each row
  when (old.turn_seat is distinct from new.turn_seat or (old.guest_uid is null and new.guest_uid is not null))
  execute function public.matches_turn_webhook();

-- 웹훅 비밀은 Vault에 둔다. 적용할 때 <secret>을 gen_random_uuid()로 만든 값으로 바꾸고, 같은 값을
-- Edge Function 시크릿 WEBHOOK_SECRET에 넣는다 (supabase secrets set WEBHOOK_SECRET=<secret>).
-- select vault.create_secret('<secret>', 'webhook_secret', 'notify-turn 웹훅 비밀');
