-- ============================================================================
-- Moldable · Little Wishes, Big River — community map
-- Run once in a NEW Supabase project (SQL editor or `supabase db push`).
--
-- Shape
--   lk_places          the five curated places; the server, not the browser, decides coordinates
--   krathong_public    what everyone may see: design, place, time, share id, and a wish ONLY after approval
--   krathong_private   never readable through the API: idempotency key, hashed client, a submitted wish
--                      waiting for moderation
--   release_krathong() the only way in: validates, rate-limits, de-duplicates, returns the confirmed record
--   lk_approve_wish() / lk_reject_wish()  moderation, for the project owner only (not granted to the API)
--
-- Private wishes never reach the server: the page only sends a wish when the visitor ticks
-- "แสดงคำอธิษฐานนี้ให้ทุกคนเห็น", and even then it stays hidden until it is approved.
-- ============================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------- places ----------------------------------------------------------
create table if not exists public.lk_places (
  id      text primary key,
  name_th text not null,
  river_th text not null,
  lng     double precision not null,
  lat     double precision not null
);
insert into public.lk_places (id, name_th, river_th, lng, lat) values
  ('chiangmai',    'เชียงใหม่',      'แม่น้ำปิง',          99.0046, 18.7876),
  ('sukhothai',    'สุโขทัย',        'ตระพังในเมืองเก่า',   99.7052, 17.0217),
  ('nakhonphanom', 'นครพนม',        'แม่น้ำโขง',          104.7935, 17.4075),
  ('bangkok',      'กรุงเทพฯ',       'แม่น้ำเจ้าพระยา',    100.4905, 13.7437),
  ('suratthani',   'สุราษฎร์ธานี',    'แม่น้ำตาปี',          99.3215,  9.1495)
on conflict (id) do update set name_th = excluded.name_th, river_th = excluded.river_th, lng = excluded.lng, lat = excluded.lat;

-- ---------- what everyone can see -------------------------------------------
create table if not exists public.krathong_public (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  place_id   text not null references public.lk_places (id),
  lng        double precision not null,                 -- copied from lk_places by the server
  lat        double precision not null,
  base       text not null check (base in ('leaf', 'lotus', 'clay')),
  flower     text not null check (flower in ('illusion', 'pigeon', 'orchid', 'marigold')),
  decor      text[] not null default '{}' check (decor <@ array['incense', 'flags', 'hearts']::text[] and cardinality(decor) <= 3),
  candle     boolean not null default true,
  share_id   text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
  wish       text check (wish is null or char_length(wish) between 1 and 120)   -- set ONLY by lk_approve_wish()
);
create index if not exists krathong_public_created_idx on public.krathong_public (created_at desc);
create index if not exists krathong_public_place_idx on public.krathong_public (place_id, created_at desc);

-- ---------- what nobody can read through the API ------------------------------
create table if not exists public.krathong_private (
  krathong_id     uuid primary key references public.krathong_public (id) on delete cascade,
  idempotency_key uuid not null unique,
  client_hash     text not null,
  wish_submitted  text check (wish_submitted is null or char_length(wish_submitted) between 1 and 120),
  wish_status     text not null default 'none' check (wish_status in ('none', 'pending', 'approved', 'rejected')),
  created_at      timestamptz not null default now()
);
create index if not exists krathong_private_client_idx on public.krathong_private (client_hash, created_at desc);

-- ---------- row level security ------------------------------------------------
alter table public.lk_places        enable row level security;
alter table public.krathong_public  enable row level security;
alter table public.krathong_private enable row level security;

drop policy if exists "places are public" on public.lk_places;
create policy "places are public" on public.lk_places for select to anon, authenticated using (true);
drop policy if exists "released krathongs are public" on public.krathong_public;
create policy "released krathongs are public" on public.krathong_public for select to anon, authenticated using (true);
-- no insert / update / delete policies anywhere: the API can only read krathong_public and lk_places,
-- and can only write through release_krathong(). krathong_private has no policy at all.

revoke all on public.lk_places, public.krathong_public, public.krathong_private from anon, authenticated;
grant select on public.lk_places, public.krathong_public to anon, authenticated;

-- ---------- the one way in ----------------------------------------------------
create or replace function public.release_krathong(
  p_idem    uuid,
  p_place   text,
  p_base    text,
  p_flower  text,
  p_decor   text[] default '{}',
  p_candle  boolean default true,
  p_wish    text default null            -- only when the visitor chose to share it publicly
)
returns table (id uuid, share_id text, created_at timestamptz, place_id text, lng double precision, lat double precision,
               base text, flower text, decor text[], candle boolean, wish_status text)
language plpgsql
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_place  public.lk_places;
  v_ip     text;
  v_hash   text;
  v_id     uuid;
  v_decor  text[];
  v_wish   text;
  v_status text := 'none';
begin
  if p_idem is null then raise exception 'missing idempotency key' using errcode = '22023'; end if;

  -- the same click twice (or a retry after a lost response) returns the first record, never a second one
  if exists (select 1 from public.krathong_private kp where kp.idempotency_key = p_idem) then
    return query
      select k.id, k.share_id, k.created_at, k.place_id, k.lng, k.lat, k.base, k.flower, k.decor, k.candle, kp.wish_status
      from public.krathong_private kp join public.krathong_public k on k.id = kp.krathong_id
      where kp.idempotency_key = p_idem;
    return;
  end if;

  select * into v_place from public.lk_places pl where pl.id = p_place;
  if not found then raise exception 'unknown place' using errcode = '22023'; end if;
  if p_base not in ('leaf', 'lotus', 'clay') then raise exception 'unknown base' using errcode = '22023'; end if;
  if p_flower not in ('illusion', 'pigeon', 'orchid', 'marigold') then raise exception 'unknown flower' using errcode = '22023'; end if;
  select coalesce(array_agg(distinct d order by d), '{}') into v_decor from unnest(coalesce(p_decor, '{}')) d;
  if not (v_decor <@ array['incense', 'flags', 'hearts']::text[]) then raise exception 'unknown decoration' using errcode = '22023'; end if;

  -- a coarse, salted hash of the caller's address: enough to rate-limit, not enough to identify anyone
  v_ip := coalesce(nullif(split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1), ''), 'unknown');
  v_hash := encode(digest(v_ip || ':moldable-loykrathong', 'sha256'), 'hex');
  if (select count(*) from public.krathong_private kp where kp.client_hash = v_hash and kp.created_at > now() - interval '10 minutes') >= 5
  or (select count(*) from public.krathong_private kp where kp.client_hash = v_hash and kp.created_at > now() - interval '1 day') >= 40 then
    raise exception 'rate_limited' using errcode = 'P0001', hint = 'Please wait a little before floating another krathong.';
  end if;

  if p_wish is not null then
    v_wish := btrim(regexp_replace(p_wish, '[[:cntrl:]]', ' ', 'g'));
    if char_length(v_wish) = 0 then v_wish := null;
    elsif char_length(v_wish) > 120 then raise exception 'wish too long' using errcode = '22023';
    elsif v_wish ~* '(https?://|www\.|[a-z0-9-]+\.(com|net|org|io|co|me|ly|th)\b|@[a-z0-9_]{2,}|line\.me|[0-9]{9,})'
      then v_status := 'rejected';                      -- links, handles and phone numbers are never published
    else v_status := 'pending';                         -- everything else waits for a person to approve it
    end if;
  end if;

  insert into public.krathong_public as k (place_id, lng, lat, base, flower, decor, candle)
  values (v_place.id, v_place.lng, v_place.lat, p_base, p_flower, v_decor, coalesce(p_candle, true))
  returning k.id into v_id;

  insert into public.krathong_private (krathong_id, idempotency_key, client_hash, wish_submitted, wish_status)
  values (v_id, p_idem, v_hash, case when v_status = 'pending' then v_wish end, v_status);

  return query
    select k.id, k.share_id, k.created_at, k.place_id, k.lng, k.lat, k.base, k.flower, k.decor, k.candle, v_status
    from public.krathong_public k where k.id = v_id;
end;
$$;
revoke all on function public.release_krathong(uuid, text, text, text, text[], boolean, text) from public;
grant execute on function public.release_krathong(uuid, text, text, text, text[], boolean, text) to anon, authenticated;

-- ---------- moderation (project owner only: SQL editor / service role) -----------
create or replace view public.lk_moderation_queue as
  select k.id, k.created_at, k.place_id, kp.wish_submitted, kp.wish_status
  from public.krathong_private kp join public.krathong_public k on k.id = kp.krathong_id
  where kp.wish_status = 'pending' order by k.created_at;
revoke all on public.lk_moderation_queue from anon, authenticated;

create or replace function public.lk_approve_wish(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.krathong_private set wish_status = 'approved' where krathong_id = p_id and wish_status = 'pending';
  if not found then raise exception 'nothing pending for %', p_id; end if;
  update public.krathong_public k set wish = kp.wish_submitted from public.krathong_private kp where kp.krathong_id = p_id and k.id = p_id;
end; $$;
create or replace function public.lk_reject_wish(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.krathong_private set wish_status = 'rejected', wish_submitted = null where krathong_id = p_id;
  update public.krathong_public set wish = null where id = p_id;
end; $$;
revoke all on function public.lk_approve_wish(uuid), public.lk_reject_wish(uuid) from public, anon, authenticated;

-- ---------- realtime: new krathongs (and approved wishes) reach open pages ----------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'krathong_public') then
    alter publication supabase_realtime add table public.krathong_public;
  end if;
end $$;
