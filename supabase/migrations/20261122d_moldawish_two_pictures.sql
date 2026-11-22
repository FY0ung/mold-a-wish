-- ============================================================================
-- Mold a Wish — two independent pictures on one krathong (additive; run after 20261122c)
--
-- A krathong may carry a base picture ("ปั้นฐานจากรูป", recipe kind 'sculpt') AND a decoration picture
-- ("ปั้นของตกแต่งจากรูป", recipe kind 'badge-cutout' | 'badge-medallion'):
--   form 'sculpt'  → sculpt = the base recipe, deco = the decoration recipe (optional)
--   form 'badge'   → sculpt = the decoration recipe (unchanged from before), deco = null
-- Recipes are compact clay patterns (≤ 8 colours × 64×64 cells, ~4 KB), never the photo itself; the original
-- picture never leaves the visitor's browser. Each is public only when the visitor chose to share it, and only
-- after a person approves it (lk_approve_clay approves both).
-- ============================================================================

alter table public.krathong_public  add column if not exists deco jsonb;
alter table public.krathong_private add column if not exists deco_submitted jsonb;
grant select (deco) on public.krathong_public to anon, authenticated;

drop function if exists public.release_krathong(uuid, text, text, text, text[], boolean, text, text, jsonb);
create or replace function public.release_krathong(
  p_idem    uuid,
  p_place   text,
  p_base    text,
  p_flower  text,
  p_decor   text[] default '{}',
  p_candle  boolean default true,
  p_wish    text default null,
  p_form    text default 'standard',
  p_sculpt  jsonb default null,           -- only when the visitor chose to share that picture's clay
  p_deco    jsonb default null            -- the decoration picture, when the base picture is there too
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

  select * into v_place from public.lk_places pl where pl.id = p_place and not pl.retired;
  if not found then raise exception 'unknown place' using errcode = '22023'; end if;
  if p_base not in ('leaf', 'lotus', 'clay') then raise exception 'unknown base' using errcode = '22023'; end if;
  if p_flower not in ('illusion', 'pigeon', 'orchid', 'marigold') then raise exception 'unknown flower' using errcode = '22023'; end if;
  if v_form not in ('standard', 'badge', 'sculpt') then raise exception 'unknown form' using errcode = '22023'; end if;
  select coalesce(array_agg(distinct d order by d), '{}') into v_decor from unnest(coalesce(p_decor, '{}')) d;
  if not (v_decor <@ array['incense', 'flags', 'hearts']::text[]) then raise exception 'unknown decoration' using errcode = '22023'; end if;
  if p_sculpt is not null then
    if v_form = 'standard' or not public.lk_valid_recipe(p_sculpt) then raise exception 'invalid clay recipe' using errcode = '22023'; end if;
    if (v_form = 'sculpt') <> ((p_sculpt ->> 'kind') = 'sculpt') then raise exception 'recipe does not match the form' using errcode = '22023'; end if;
    v_sstat := 'pending';
  end if;
  if p_deco is not null then
    if v_form <> 'sculpt' or not public.lk_valid_recipe(p_deco) or (p_deco ->> 'kind') = 'sculpt' then raise exception 'invalid decoration recipe' using errcode = '22023'; end if;
    v_sstat := 'pending';
  end if;

  v_ip := coalesce(nullif(split_part(coalesce(coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for', ''), ',', 1), ''), 'unknown');
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

  insert into public.krathong_private (krathong_id, idempotency_key, client_hash, wish_submitted, wish_status, sculpt_submitted, deco_submitted, sculpt_status)
  values (v_id, p_idem, v_hash, case when v_status = 'pending' then v_wish end, v_status, p_sculpt, p_deco, v_sstat);

  return query
    select k.id, k.share_id, k.created_at, k.place_id, k.lng, k.lat, k.base, k.flower, k.decor, k.candle, v_status, k.form, v_sstat
    from public.krathong_public k where k.id = v_id;
end;
$$;
revoke all on function public.release_krathong(uuid, text, text, text, text[], boolean, text, text, jsonb, jsonb) from public;
grant execute on function public.release_krathong(uuid, text, text, text, text[], boolean, text, text, jsonb, jsonb) to anon, authenticated;

-- ---------- moderation of shared clay (project owner only; both pictures together) ----------
drop view if exists public.lk_clay_queue;
create view public.lk_clay_queue with (security_invoker = true) as
  select k.id, k.created_at, k.place_id, k.form, kp.sculpt_submitted, kp.deco_submitted, kp.sculpt_status
  from public.krathong_private kp join public.krathong_public k on k.id = kp.krathong_id
  where kp.sculpt_status = 'pending' order by k.created_at;
revoke all on public.lk_clay_queue from anon, authenticated;
alter view public.lk_moderation_queue set (security_invoker = true);   -- owner-only either way; no definer view in the API schema

create or replace function public.lk_approve_clay(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.krathong_private set sculpt_status = 'approved' where krathong_id = p_id and sculpt_status = 'pending';
  if not found then raise exception 'nothing pending for %', p_id; end if;
  update public.krathong_public k set sculpt = kp.sculpt_submitted, deco = kp.deco_submitted from public.krathong_private kp where kp.krathong_id = p_id and k.id = p_id;
end; $$;
create or replace function public.lk_reject_clay(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.krathong_private set sculpt_status = 'rejected', sculpt_submitted = null, deco_submitted = null where krathong_id = p_id;
  update public.krathong_public set sculpt = null, deco = null where id = p_id;
end; $$;
revoke all on function public.lk_approve_clay(uuid), public.lk_reject_clay(uuid) from public, anon, authenticated;
