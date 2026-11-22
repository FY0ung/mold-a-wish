-- ============================================================================
-- Mold a Wish — no manual moderation: a wish the visitor chose to share is public as soon as the krathong is released
-- (run after 20261123_moldawish_clay_public_on_release)
--
--   · p_wish is sent by the page ONLY when the visitor ticked "แสดงคำอธิษฐานนี้บนแผนที่ของทุกคน"; a private wish is never sent.
--   · a shared wish that passes the automatic checks (≤ 120 characters; no links, @handles or phone numbers) is written to
--     krathong_public.wish at release, status 'approved'. One that fails them stays off the public table ('rejected'),
--     and the krathong itself is still released. Nobody reviews anything.
--   · the two wishes already waiting under the old rules ('pending') are published the same way.
-- Same signature, grants, validation, rate limit and idempotency; no table or RLS change.
-- ============================================================================

create or replace function public.release_krathong(
  p_idem    uuid,
  p_place   text,
  p_base    text,
  p_flower  text,
  p_decor   text[] default '{}',
  p_candle  boolean default true,
  p_wish    text default null,
  p_form    text default 'standard',
  p_sculpt  jsonb default null,           -- the clay recipe of the picture (never the photo)
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
    v_sstat := 'approved';
  end if;
  if p_deco is not null then
    if v_form <> 'sculpt' or not public.lk_valid_recipe(p_deco) or (p_deco ->> 'kind') = 'sculpt' then raise exception 'invalid decoration recipe' using errcode = '22023'; end if;
    v_sstat := 'approved';
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
    else v_status := 'approved';                          -- shared wishes are public at once (no review)
    end if;
  end if;

  insert into public.krathong_public as k (place_id, lng, lat, base, flower, decor, candle, form, sculpt, deco, wish)
  values (v_place.id, v_place.lng, v_place.lat, p_base, p_flower, v_decor, coalesce(p_candle, true), v_form, p_sculpt, p_deco,
          case when v_status = 'approved' then v_wish end)
  returning k.id into v_id;

  insert into public.krathong_private (krathong_id, idempotency_key, client_hash, wish_submitted, wish_status, sculpt_submitted, deco_submitted, sculpt_status)
  values (v_id, p_idem, v_hash, case when v_status = 'approved' then v_wish end, v_status, p_sculpt, p_deco, v_sstat);

  return query
    select k.id, k.share_id, k.created_at, k.place_id, k.lng, k.lat, k.base, k.flower, k.decor, k.candle, v_status, k.form, v_sstat
    from public.krathong_public k where k.id = v_id;
end;
$$;
revoke all on function public.release_krathong(uuid, text, text, text, text[], boolean, text, text, jsonb, jsonb) from public;
grant execute on function public.release_krathong(uuid, text, text, text, text[], boolean, text, text, jsonb, jsonb) to anon, authenticated;

-- the wishes that were waiting for review under the old rules: their owners chose to share them, so they go public now
update public.krathong_public k set wish = kp.wish_submitted
  from public.krathong_private kp
  where kp.krathong_id = k.id and kp.wish_status = 'pending' and kp.wish_submitted is not null;
update public.krathong_private set wish_status = 'approved' where wish_status = 'pending' and wish_submitted is not null;
