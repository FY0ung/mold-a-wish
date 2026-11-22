-- ============================================================================
-- Moldable · Little Wishes, Big River — krathong forms (additive; run after 20261122_loykrathong_community.sql)
--
-- form    'standard'  a handcrafted krathong
--         'badge'     with a picture made into a clay piece on a clay base
--         'sculpt'    with a picture sculpted into a clay figure, seated in the middle
-- sculpt  the clay RECIPE (never the picture): { v:1, kind, cameo, pal:[≤ 8 "#rrggbb"], idx: 64×64 chars "0"–"7" or "." }
--         public only when the visitor chose to share it, and only after approval (like a wish)
-- Existing rows stay 'standard'; release_krathong() keeps working for callers that do not send the new fields.
-- ============================================================================

alter table public.krathong_public  add column if not exists form text not null default 'standard';
alter table public.krathong_public  add column if not exists sculpt jsonb;
alter table public.krathong_private add column if not exists sculpt_submitted jsonb;
alter table public.krathong_private add column if not exists sculpt_status text not null default 'none';
do $$ begin
  alter table public.krathong_public add constraint krathong_public_form_chk check (form in ('standard', 'badge', 'sculpt'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.krathong_private add constraint krathong_private_sculpt_status_chk check (sculpt_status in ('none', 'pending', 'approved', 'rejected'));
exception when duplicate_object then null; end $$;
grant select (form, sculpt) on public.krathong_public to anon, authenticated;

/** A recipe is accepted only in its exact shape and size. */
create or replace function public.lk_valid_recipe(r jsonb) returns boolean
language sql immutable set search_path = public as $$
  select r is not null
     and jsonb_typeof(r) = 'object'
     and octet_length(r::text) <= 6000
     and (r ->> 'v') = '1'
     and (r ->> 'kind') in ('sculpt', 'badge-cutout', 'badge-medallion')
     and jsonb_typeof(r -> 'pal') = 'array' and jsonb_array_length(r -> 'pal') between 1 and 8
     and not exists (select 1 from jsonb_array_elements_text(r -> 'pal') c where c !~ '^#[0-9a-fA-F]{6}$')
     and jsonb_typeof(r -> 'idx') = 'string' and char_length(r ->> 'idx') = 4096 and (r ->> 'idx') ~ '^[0-7.]+$'
     and (r -> 'cameo' is null or jsonb_typeof(r -> 'cameo') = 'boolean')
     and (select count(*) from jsonb_object_keys(r)) <= 5;
$$;

drop function if exists public.release_krathong(uuid, text, text, text, text[], boolean, text);
create or replace function public.release_krathong(
  p_idem    uuid,
  p_place   text,
  p_base    text,
  p_flower  text,
  p_decor   text[] default '{}',
  p_candle  boolean default true,
  p_wish    text default null,
  p_form    text default 'standard',
  p_sculpt  jsonb default null            -- only when the visitor chose to share their clay
)
returns table (id uuid, share_id text, created_at timestamptz, place_id text, lng double precision, lat double precision,
               base text, flower text, decor text[], candle boolean, wish_status text, form text, sculpt_status text)
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
  v_form   text := coalesce(p_form, 'standard');
  v_sstat  text := 'none';
begin
  if p_idem is null then raise exception 'missing idempotency key' using errcode = '22023'; end if;
  if exists (select 1 from public.krathong_private kp where kp.idempotency_key = p_idem) then
    return query
      select k.id, k.share_id, k.created_at, k.place_id, k.lng, k.lat, k.base, k.flower, k.decor, k.candle, kp.wish_status, k.form, kp.sculpt_status
      from public.krathong_private kp join public.krathong_public k on k.id = kp.krathong_id
      where kp.idempotency_key = p_idem;
    return;
  end if;

  select * into v_place from public.lk_places pl where pl.id = p_place;
  if not found then raise exception 'unknown place' using errcode = '22023'; end if;
  if p_base not in ('leaf', 'lotus', 'clay') then raise exception 'unknown base' using errcode = '22023'; end if;
  if p_flower not in ('illusion', 'pigeon', 'orchid', 'marigold') then raise exception 'unknown flower' using errcode = '22023'; end if;
  if v_form not in ('standard', 'badge', 'sculpt') then raise exception 'unknown form' using errcode = '22023'; end if;
  select coalesce(array_agg(distinct d order by d), '{}') into v_decor from unnest(coalesce(p_decor, '{}')) d;
  if not (v_decor <@ array['incense', 'flags', 'hearts']::text[]) then raise exception 'unknown decoration' using errcode = '22023'; end if;
  if p_sculpt is not null then
    if v_form = 'standard' or not public.lk_valid_recipe(p_sculpt) then raise exception 'invalid clay recipe' using errcode = '22023'; end if;
    if (v_form = 'sculpt') <> ((p_sculpt ->> 'kind') = 'sculpt') then raise exception 'recipe does not match the form' using errcode = '22023'; end if;
    v_sstat := 'pending';                                   -- a person approves it before anyone else sees it
  end if;

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
    elsif v_wish ~* '(https?://|www\.|[a-z0-9-]+\.(com|net|org|io|co|me|ly|th)\b|@[a-z0-9_]{2,}|line\.me|[0-9]{9,})' then v_status := 'rejected';
    else v_status := 'pending';
    end if;
  end if;

  insert into public.krathong_public as k (place_id, lng, lat, base, flower, decor, candle, form)
  values (v_place.id, v_place.lng, v_place.lat, p_base, p_flower, v_decor, coalesce(p_candle, true), v_form)
  returning k.id into v_id;

  insert into public.krathong_private (krathong_id, idempotency_key, client_hash, wish_submitted, wish_status, sculpt_submitted, sculpt_status)
  values (v_id, p_idem, v_hash, case when v_status = 'pending' then v_wish end, v_status, case when v_sstat = 'pending' then p_sculpt end, v_sstat);

  return query
    select k.id, k.share_id, k.created_at, k.place_id, k.lng, k.lat, k.base, k.flower, k.decor, k.candle, v_status, k.form, v_sstat
    from public.krathong_public k where k.id = v_id;
end;
$$;
revoke all on function public.release_krathong(uuid, text, text, text, text[], boolean, text, text, jsonb) from public;
grant execute on function public.release_krathong(uuid, text, text, text, text[], boolean, text, text, jsonb) to anon, authenticated;

-- ---------- moderation of shared clay (project owner only) ----------
create or replace view public.lk_clay_queue as
  select k.id, k.created_at, k.place_id, k.form, kp.sculpt_submitted, kp.sculpt_status
  from public.krathong_private kp join public.krathong_public k on k.id = kp.krathong_id
  where kp.sculpt_status = 'pending' order by k.created_at;
revoke all on public.lk_clay_queue from anon, authenticated;

create or replace function public.lk_approve_clay(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.krathong_private set sculpt_status = 'approved' where krathong_id = p_id and sculpt_status = 'pending';
  if not found then raise exception 'nothing pending for %', p_id; end if;
  update public.krathong_public k set sculpt = kp.sculpt_submitted from public.krathong_private kp where kp.krathong_id = p_id and k.id = p_id;
end; $$;
create or replace function public.lk_reject_clay(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.krathong_private set sculpt_status = 'rejected', sculpt_submitted = null where krathong_id = p_id;
  update public.krathong_public set sculpt = null where id = p_id;
end; $$;
revoke all on function public.lk_approve_clay(uuid), public.lk_reject_clay(uuid) from public, anon, authenticated;
