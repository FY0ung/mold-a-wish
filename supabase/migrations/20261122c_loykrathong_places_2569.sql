-- Moldable · Little Wishes, Big River — the 2569 places (additive; run after 20261122b)
--
-- The map now offers the 20 Loy Krathong events of 2569 listed by thailandexhibition.com
-- ("รวม 20 งานลอยกระทง ปี 2569 ทั่วไทย"). Coordinates are venue-level prototype placements.
-- The five earlier demonstration places stay in lk_places (older rows reference them); they are marked retired
-- and release_krathong() keeps working for every place in the table — the browser only offers the 20 below.

alter table public.lk_places add column if not exists retired boolean not null default false;
update public.lk_places set retired = true where id in ('chiangmai', 'nakhonphanom', 'bangkok', 'suratthani');

insert into public.lk_places (id, name_th, river_th, lng, lat) values
  ('riverfest',    'ริมเจ้าพระยา', 'แม่น้ำเจ้าพระยา', 100.4880, 13.7550),
  ('bangkae',      'บางแค', 'M GREEN PARK', 100.4072, 13.7127),
  ('songwat',      'ทรงวาด', 'ย่านทรงวาด', 100.5083, 13.7392),
  ('iconsiam',     'ไอคอนสยาม', 'แม่น้ำเจ้าพระยา', 100.5112, 13.7263),
  ('measpark',     'MEA SPARK', 'ย่านวัดเลียบ', 100.4978, 13.7405),
  ('museumsiam',   'มิวเซียมสยาม', 'ลานมิวเซียมสยาม', 100.4942, 13.7443),
  ('kokret',       'เกาะเกร็ด', 'แม่น้ำเจ้าพระยา', 100.4872, 13.9120),
  ('samutsakhon',  'สมุทรสาคร', 'แม่น้ำท่าจีน', 100.2762, 13.5452),
  ('ayutthaya',    'อยุธยา', 'อุทยานประวัติศาสตร์อยุธยา', 100.5583, 14.3558),
  ('japanvillage', 'หมู่บ้านญี่ปุ่น', 'หมู่บ้านญี่ปุ่น อยุธยา', 100.5792, 14.3300),
  ('kanchanaburi', 'กาญจนบุรี', 'ท่าเทียบแพ ปากแพรก', 99.5170, 14.0262),
  ('sukhothai',    'สุโขทัย', 'อุทยานประวัติศาสตร์สุโขทัย', 99.7052, 17.0217),
  ('phitsanulok',  'พิษณุโลก', 'แม่น้ำน่าน', 100.2637, 16.8262),
  ('phrae',        'แพร่', 'วัดจอมสวรรค์', 100.1482, 18.1508),
  ('chiangsaen',   'เชียงแสน', 'แม่น้ำโขง', 100.0898, 20.2748),
  ('fangmin',      'วัดฝั่งหมิ่น', 'แม่น้ำกก', 99.8336, 19.9172),
  ('phetchabun',   'เพชรบูรณ์', 'วัดไตรภูมิ', 101.1564, 16.4196),
  ('wangthong',    'บึงราชนก', 'บึงราชนก', 100.4198, 16.8085),
  ('khonkaen',     'บึงสีฐาน', 'บึงสีฐาน', 102.8176, 16.4747),
  ('muangtam',     'ปราสาทเมืองต่ำ', 'บารายเมืองต่ำ', 102.9812, 14.4982)
on conflict (id) do update set name_th = excluded.name_th, river_th = excluded.river_th, lng = excluded.lng, lat = excluded.lat, retired = false;
