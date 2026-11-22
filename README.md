# Moldable — Little Wishes, Big River

Desktop visual prototype (design viewport **1440 × 900**) of an interactive Loy Krathong experience.
Plain HTML: no framework, no build step. Mobile layouts are intentionally out of scope for this phase.

## Open it

- Double-click `index.html` (works from `file://`), **or**
- double-click `serve.command` → http://localhost:4173 (runs `python3 -m http.server` in this folder).

An internet connection is needed for the libraries (CDN) and for the map tiles.

## What is in here

```
index.html                     structure · styles · all interaction and animation logic (one inline module)
assets/characters/*.svg        the five original Moldable Crew silhouettes (copied unchanged from morph/scripts/hero3d/src/characters)
assets/characters/characters.js  the same SVGs as a classic script, so the page also opens from file://
assets/characters/render/      original still renders — only used by the "WebGL unavailable" fallback
assets/fonts/Poppins-*.ttf     Moldable's typeface (copied from morph/src/material/fonts/Poppins)
assets/fonts/NotoSansThai-*    Thai fallback Moldable declares after Poppins (Noto Sans Thai, SIL OFL 1.1, via @fontsource)
config.js                      where the community map lives (empty = not connected)
supabase/migrations/*.sql      the community database: tables, row-level security, release + moderation functions
                               (run 20261122_… first, then 20261122b_… — the krathong forms, additive)
assets/brand/                  Moldable logo (logo.svg, the one Morph's app bar uses) + lockup + favicon (copied from morph/public)
```

## The flow (craft-first revision)

The page opens **straight into crafting** — there is no intro screen.
Craft (base · flowers · decorations) → Wish (candle) → Journey → Choose a river (real map) → Float → Done → again.

## App bar and theme (aligned with Morph)

- **App bar** — rebuilt from Morph's `sections/landing/layout/app-bar.tsx` + `cta-eyes.tsx`, styled with the values in
  `landing-corrections.css` and `landing.css`: 57 px tall incl. a 1 px line (`--border-default`), the page canvas at 16 %
  with `blur(24px)`, Morph's content gutter (120 px at 1440), the logo at 40 px tall / `clamp(104px, 8.5vw, 160px)`
  (inverted on Light), Theme and Sound as 40 × 40 round IconButtons, and the eye pill (Pigeon 700 / 100, hover 800,
  pupils follow the pointer). The Loy Krathong steps sit in the middle.
- **ปั้นกระทงใหม่** — the eye pill starts over. If something would be lost (a changed krathong, a wish, a lit candle,
  or any scene after crafting) a small card asks first (ยกเลิก / เริ่มใหม่; Esc or a click outside closes it). On the
  last scene it starts over at once. The logo uses the same path.
- **Light / Dark** — `html[data-theme]`, Light by default, remembered under Morph's own key `morph-theme`, set by an
  inline script before the first paint (no flash), switched in one frame (`mw-theme-switching`). Tokens are Morph's
  Light/Dark semantic tokens plus the Studio's `globals.css` `.dark` values. The Dark page background is the live
  moldable.studio black `#0C0D0D` (its computed `rgb(12, 13, 13)`), which is newer than the local Morph `globals.css`;
  panels and cards keep Morph's `#2B2B2B` / `#1F1F1F` surfaces on top of it. The 3D scene changes its lighting, water and
  lantern air only (no geometry); the map swaps between ELEMNT Mirage Light and Mirage Dark without moving, and the
  pins, selection and progress stay as they are.
- **Thai only** — no language switch; map labels are Thai-first.

## The crew's gaze and the music

- **Gaze** — the original pupils glide inside their own whites (and the body turns very slightly) towards what the visitor
  is working on: in crafting MIN watches the top of the krathong, FAMAI the flower ring, PAI the candle; in the wish FAH
  watches the candle, and the wish while it is being typed; on the map ACT watches the chosen place; in the journey, float
  and last scene everyone watches the krathong. Faces, shapes and positions are unchanged. With reduced motion the eyes
  still point, without the slow idle wander.
- **Music — prototype placeholder, for review.** An original, slow ram-wong-style tune synthesised in the browser: a
  ranat-like melody in D major pentatonic (long notes rolled the way a ranat player does), a soft echo, a low plucked
  bass and the ching–chap of small hand cymbals, ~55 s loop. It is *not* "วันเพ็ญเดือน 12" — that song is still under
  copyright, so its melody is not reproduced. To use a licensed recording, put it in `assets/audio/` and set `MUSIC_FILE`
  at the top of the sound section in `index.html`.
- **Mix** — the music plays only while the sound switch is on (it fades in over 2.5 s and out when switched off or when the
  tab is hidden). Its peaks sit about 4 dB under the effects, and it dips to 42 % for about a second under every effect.
  The effects themselves are unchanged.

## Community map · "เริ่มลอยกระทง" · IG Story

**Appbar CTA "เริ่มลอยกระทง"** (same Morph eye pill, new label) opens the ELEMNT map with everyone's krathongs.
It never resets or publishes anything. With a krathong in progress (changed design, a wish, a lit candle, or from the
wish scene) the map keeps the float flow (choose a place → ลอยที่นี่เลย). With nothing made yet it is an explore view
with "ปั้นกระทงของคุณ" back to the table. A normal visit still opens straight into crafting.

**Three modes, always labelled on screen**
| Mode | When | What the map shows |
|---|---|---|
| Not connected | `config.js` empty (as shipped) | Only your own krathong (local), with the line "แผนที่ชุมชนยังไม่ได้เชื่อมต่อฐานข้อมูล…" |
| Live | `config.js` has a Supabase URL + anon key | Real krathongs from the shared database; new ones appear live (Realtime), or every 30 s if the socket drops |
| Demo | `?demo=1` | 74 sample krathongs + a banner "โหมดสาธิต · …ไม่ใช่ของผู้ใช้จริง"; releases stay in this browser |

**Turning the live mode on**
1. Create a Supabase project (for this site only).
2. Run `supabase/migrations/20261122_loykrathong_community.sql` in its SQL editor.
3. Put the project URL and the **anon / publishable** key in `config.js` (never the service-role key), and
   `publicSiteUrl` once the site is published (needed for "คัดลอกลิงก์กระทง").
4. Approve shared wishes in the SQL editor: `select * from lk_moderation_queue;` then
   `select lk_approve_wish('<id>');` or `select lk_reject_wish('<id>');`.

**What is stored, and who can see it**
- `krathong_public` (readable by everyone): id, time, place, server-set coordinates, base, flower, decorations, candle,
  share id, and a wish **only after approval**.
- `krathong_private` (not readable through the API at all): idempotency key, a salted hash of the caller's IP (rate
  limit only), a wish waiting for moderation.
- The browser can only write through `release_krathong()`: it validates place / base / flower / decorations against
  fixed lists, takes coordinates from `lk_places` (never from the browser), limits 5 releases per 10 min and 40 per day
  per address, returns the first record again for a repeated idempotency key (double clicks, retries, replays), and
  never publishes wishes with links, handles or phone numbers.
- A wish is private by default and never leaves the device unless the visitor ticks "แสดงคำอธิษฐานนี้บนแผนที่ของทุกคน".
  Before floating, the place card says the design and place will be visible to everyone.

**Markers** are the visitor's real krathong, rendered in the browser from its design (same clay parts as the 3D
krathong). Up to 14 sit around each place at a stable pixel offset derived from the id (visual only: stored coordinates
stay exact); the rest gather in a glowing "+N" chip that opens a grid and loads older ones on request. A card shows the
krathong, where and when it was floated, and an approved wish, nothing else.

**Story image** (done screen): a 1080 × 1920 PNG drawn on its own canvas (night river in the Moldable palette, the logo,
"LITTLE WISHES, BIG RIVER", the visitor's krathong rendered from its design, "คำอธิษฐานของฉัน / ออกเดินทางแล้ว ♡", the
place, the wish only if "แสดงคำอธิษฐานในภาพ Story" is ticked (off by default), "มาลอยกระทงด้วยกัน!", and the site host
once `publicSiteUrl` is set). "แชร์ลง IG Story" opens the device share sheet when the browser can share image files
(mostly phones over https); otherwise it downloads the PNG and says how to add it in Instagram. Nothing is posted to
Instagram directly. "ดาวน์โหลดภาพ Story" always downloads.

**Share link** `?k=<share id>` opens the map on that krathong in any browser. It is only offered in live mode with a
real https address; on file:// or localhost the button stays disabled and says why.

## The map round: clay pins · start from a pin · ดูแม่น้ำ · ปั้นของตกแต่งจากรูป

**Pins.** Each place is a puffy clay bead holding a tiny krathong, on its own ring of water, with its name under it.
Hover lifts it and warms the halo; pressing squashes it; the selected place turns warm (illusion/marigold clay), grows,
lights its candle and sends out ripples; keyboard focus gets the Morph ring. Place pins always sit above the
krathongs. Other visitors' krathongs sit on small pools of light around their place (closer together and a little
smaller when the whole country is in view, spread out when zoomed in); yours wears a ring and a "ของคุณ" tag; extra
ones gather in a clay "+N" pill.

**Start from a pin.** Clicking a place opens the right-hand panel: the place, its waterway, a line about it, and
what you can do there.
- No krathong yet: **เลือกกระทง** (to the table, the place stays chosen) · **ดูแม่น้ำ** · **ปั้นของตกแต่งจากรูป**.
- Holding a krathong: **ใช้กระทงนี้** (float it here) · **ดูแม่น้ำ** · **เปลี่ยนกระทง** · **ปั้นของตกแต่งจากรูป**.
After crafting from a pin, the journey brings you back to that place with its panel open.

**ดูแม่น้ำ.** The map flies down to the place and fades into a 3D river built for it: water, a far bank with trees,
a golden chedi and lantern posts, the moon, sky lanterns. Up to 14 of tonight's krathongs at that place drift
downstream (the newest first); yours floats front and centre with a "กระทงของคุณ" tag. The heading says how many
krathongs are at this place (or that the community map isn't connected / that it is demo data). From here: back to
the map, float your krathong here, or choose / make one.

**How a picture becomes clay** (both picture options below use this). Choose a PNG or JPG (or drop it in). In the browser, on a
256 px square: the picture's own transparency is kept; otherwise a plain background is lifted off from the edges
(if the background is busy, the whole picture is used). Colours are flattened into a few soft clay tones, a height
field adds rounded edges, grooves between colour areas and a little relief, and a normal map carries it. With a
separable subject it becomes a puffy clay piece in its own silhouette (traced and inflated like the characters);
otherwise a round clay medallion with a rim, the subject raised as a cameo when it can be. Either way it stands on a
small clay base on the krathong, front-right of the candle. Shape, size and position can be adjusted with a live lit
preview. The picture never leaves the browser and is not part of the public record (the community sees the krathong
without it); it does appear in your Story image and in the river view.

## Two ways to use a picture: one in each tab

The tab decides what the picture becomes; there is no separate "which mode?" choice any more.
- **ฐาน → ปั้นฐานจากรูป** — under the three base options, in a "จากรูปของคุณ" row. The picture becomes the
  krathong's centrepiece: a chunky clay form standing in the middle of the chosen base (the candle moves to its
  front-left). The subject's silhouette is inflated like the Moldable characters (Poisson "balloon"), the clay relief
  is pushed into the geometry itself, the front wears the clay tones and the back is plain clay in the figure's
  average tone. When the subject cannot be separated from its background, it becomes a soft clay pebble of the whole
  picture (and says so). Once applied the card reads "ฐานจากรูปของคุณ · ตั้งเด่นบน<base>".
- **ของตกแต่ง → ปั้นของตกแต่งจากรูป** — under the decorations, in the same "จากรูปของคุณ" row. A small clay piece
  (own silhouette or round medallion, with a shape toggle) on a clay base, beside the candle. The map panel's picture
  shortcut opens this one.
Both open the same dialog, titled for the tab (MIN · ช่างปั้นฐาน / PAI · นักแต่งกระทง), with its own button
("ปั้นเป็นฐาน" / "ปั้นเป็นของตกแต่ง"). A krathong carries one picture: if the other kind is already on it, the
card and the dialog say it will be replaced, and the same picture is reused so it need not be chosen again.
A live render of the result on the visitor's own krathong is shown before applying. The krathong's record says which
it is: `form` = `standard` · `badge` · `sculpt`.

**In the community river.** The picture never leaves the browser. If the visitor ticks "แบ่งปันเคลย์นี้บนแผนที่ของ
ทุกคน", a compact *clay recipe* is sent instead — up to 8 clay tones and a 64 × 64 map of which tone goes where
(about 4 KB; enough to rebuild the same clay piece, not the photo). It is stored privately until approved
(`select * from lk_clay_queue;` → `select lk_approve_clay('<id>');` / `lk_reject_clay`), then appears for everyone
(Realtime updates open pages). Until then others see the krathong without the clay. In the river, up to 12 krathongs
float at once; up to 6 of them with clay from pictures are woven in among the handcrafted ones, and they turn their
front to the viewer and only sway, so the figures stay readable. Demo mode (`?demo=1`) includes sample clay figures
made from ten simple drawn "favourite things", labelled as sample data.

## Where things come from

- **Characters** — the five original Moldable Crew silhouettes, built by the engine ported unchanged from
  `morph/scripts/hero3d/src/hero3d.js` (outline → `inflate()` → soft-jelly material). They work as a rotating cast:
  MIN at the table for the base tab, FAMAI (holding a flower in the chosen colour) for flowers, PAI (holding a clay
  heart) for decorations — whoever is not on duty settles at the side of the pier. For the wish the makers step back and fade
  out, so FAH is the only character on screen: it floats in beside the krathong and lights the candle (back in
  crafting, the makers return); ACT guides on the map and waves goodbye; all five gather in the last scene.
- **The Loy Krathong night** — the source project has no festival or environment assets, so the world is new and
  procedural, in the same clay material: a crafting pier on a glossy, pearl-blue tile of river (the whole world sits in Moldable's soft ivory palette while crafting; it only turns to night for the journey to the map), a far bank with a chedi,
  a two-roofed sala and small houses with lit windows, round trees, an arched footbridge, a moon (a shaded sphere: moon-cream with soft maria, shallow craters, limb darkening, two-layer halo) framed by puffy clustered clay clouds (flat undersides, lighter tops, paler ones farther back), its path on
  the water, sky lanterns (stylised khom loy: a paper-shader lathe body with seams, bamboo hoop, flame, inner glow and halo; they rise slowly on their own cycles, sway, drift away and fade, nearer ones larger and brighter; 20 lanterns spread over the whole frame in three depths — a few large ones at the edges and corners, medium ones across the central sky, small soft ones high from left to right), small krathongs that bob with their candles, festival bulbs and paper lanterns
  over the pier, warm point lights. The backdrop is a creamy CSS gradient built from the Moldable lilac, pigeon and illusion 100 tokens, behind the transparent 3D canvas.
- **Krathong parts, table** — new, made for this prototype with the same clay material (the source project has none).
- **Design tokens** — reproduced from `morph/src/app/globals.css` and `studio.css` §1 (colours, radius, shadows, motion).
- **Map** — ELEMNT Cartographer only: style "Mirage" in the page's theme
  (Light `https://carto.elemnt.earth/2026-06-23_mirage/style.json`, Dark `.../style.dark.json`), MapLibre GL JS 4 + PMTiles 4, with the
  OpenStreetMap / Protomaps credit and the "Powered by ELEMNT" link. If it cannot load, a retry state is shown — no
  other map provider is used.
- **Libraries (CDN)** — three 0.170.0 (the version the Moldable engine is built on), GSAP 3.12.5, maplibre-gl 4, pmtiles 4.

## Prototype limits (honest list)

- As shipped (config.js empty) nothing is sent anywhere: your last krathongs are remembered in this browser only.
  With a Supabase project configured, released krathongs are stored as described above.
- The five places are demonstration locations; each point sits on water in the ELEMNT basemap. The drift is decorative,
  not a river-current simulation.
- Water reflections are stylised (glossy material + streaks of light), not real-time reflections.
- Sound is a handful of synthesised cues (Web Audio), off until switched on.
- Desktop only. Below ~1180 px wide the layout is not adapted.

`window.__proto` exposes the state for QA in the console.
