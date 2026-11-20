-- ============================================================
-- GoldNovel — Supabase Database Schema (ก๊อปทั้งหมดไปกด Run ครั้งเดียว)
-- วิธีใช้: เปิด Supabase -> SQL Editor -> New Query -> วางโค้ดนี้ -> กด Run
-- ============================================================

-- 1. ตารางข้อมูลสมาชิกและยอดเหรียญ
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  coin_balance integer not null default 0 check (coin_balance >= 0),
  role text not null default 'reader' check (role in ('reader', 'admin')),
  created_at timestamptz not null default now()
);

-- สร้างโปรไฟล์อัตโนมัติเมื่อมีคนสมัครสมาชิกใหม่
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. ตารางตั้งค่าหน้าเว็บ (Hero Banner และป้ายโปรโมชัน ปรับแก้จากหน้า /admin)
create table if not exists public.site_settings (
  id text primary key default 'main',
  hero_title text not null default 'มรรคาเหนือหล้า มหาปราชญ์แห่งยุทธภพ',
  hero_tagline text not null default 'เมื่อก้าวข้ามขีดจำกัด... จักกลายเป็นผู้ยืนอยู่เหนือฟ้า',
  hero_banner_url text default '',
  promo_title text not null default 'เติมเงินวันนี้ รับโบนัสเพิ่ม 20%',
  promo_subtitle text not null default 'รองรับพร้อมเพย์และทรูมันนี่ วอลเล็ท อัตโนมัติ',
  promo_banner_url text default '',
  updated_at timestamptz not null default now()
);

insert into public.site_settings (id) values ('main') on conflict (id) do nothing;

-- 3. ตารางนิยาย
create table if not exists public.novels (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  author text not null default 'GoldNovel',
  synopsis text default '',
  cover_url text default '',
  categories text[] not null default array['แฟนตาซี'],
  audience text not null default 'ทั้งหมด' check (audience in ('ทั้งหมด', 'ชาย', 'หญิง')),
  status text not null default 'กำลังอัปเดต' check (status in ('กำลังอัปเดต', 'จบแล้ว')),
  views integer not null default 0,
  is_featured boolean not null default false,
  created_at timestamptz not null default now()
);

-- 4. ตารางตอนนิยาย
create table if not exists public.chapters (
  id uuid primary key default gen_random_uuid(),
  novel_id uuid not null references public.novels(id) on delete cascade,
  chapter_number integer not null,
  title text not null,
  content text not null,
  price_coins integer not null default 0 check (price_coins >= 0),
  created_at timestamptz not null default now(),
  unique (novel_id, chapter_number)
);

-- 5. ตารางตอนที่ปลดล็อกแล้ว (ป้องกันการคิดเหรียญซ้ำ)
create table if not exists public.unlocked_chapters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  chapter_id uuid not null references public.chapters(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  unique (user_id, chapter_id)
);

-- 6. ตารางคลังหนังสือและความคืบหน้าการอ่าน
create table if not exists public.bookmarks_progress (
  user_id uuid not null references public.profiles(id) on delete cascade,
  novel_id uuid not null references public.novels(id) on delete cascade,
  is_bookmarked boolean not null default true,
  last_chapter_id uuid references public.chapters(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (user_id, novel_id)
);

-- 7. ตารางประวัติการเติมเงินและการใช้เหรียญ
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('topup', 'unlock')),
  amount_baht numeric(10,2) default 0,
  coins_delta integer not null,
  payment_method text default '',
  slip_url text default '',
  slip_ref text unique,
  note text default '',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now()
);

-- 8. ฟังก์ชันตรวจสอบสิทธิ์ Admin
create or replace function public.is_admin()
returns boolean
language sql
security definer stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- 9. ฟังก์ชันปลดล็อกตอนอย่างปลอดภัยบนเซิร์ฟเวอร์ (ตัดเหรียญ + บันทึกสิทธิ์พร้อมกัน)
create or replace function public.unlock_chapter(p_chapter_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_price integer;
  v_title text;
  v_balance integer;
begin
  if v_user_id is null then
    raise exception 'กรุณาเข้าสู่ระบบก่อนปลดล็อกตอน';
  end if;

  select price_coins, title into v_price, v_title
  from public.chapters where id = p_chapter_id;

  if not found then
    raise exception 'ไม่พบตอนนิยายนี้';
  end if;

  if v_price = 0 or exists (
    select 1 from public.unlocked_chapters
    where user_id = v_user_id and chapter_id = p_chapter_id
  ) then
    return jsonb_build_object('status', 'already_unlocked');
  end if;

  select coin_balance into v_balance
  from public.profiles where id = v_user_id for update;

  if v_balance < v_price then
    raise exception 'เหรียญไม่เพียงพอ';
  end if;

  update public.profiles
  set coin_balance = coin_balance - v_price
  where id = v_user_id;

  insert into public.unlocked_chapters (user_id, chapter_id)
  values (v_user_id, p_chapter_id);

  insert into public.transactions (user_id, type, coins_delta, note, status)
  values (v_user_id, 'unlock', -v_price, 'ปลดล็อก: ' || v_title, 'approved');

  return jsonb_build_object('status', 'unlocked', 'new_balance', v_balance - v_price);
end;
$$;

-- 10. ฟังก์ชันอนุมัติรายการเติมเงิน (สำหรับ Admin หรือ SlipOK Edge Function)
create or replace function public.approve_topup(p_tx_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_tx record;
begin
  if not public.is_admin() then
    raise exception 'เฉพาะผู้ดูแลระบบเท่านั้น';
  end if;

  select * into v_tx from public.transactions
  where id = p_tx_id and type = 'topup' and status = 'pending'
  for update;

  if not found then
    raise exception 'ไม่พบรายการรออนุมัติ';
  end if;

  update public.transactions set status = 'approved' where id = p_tx_id;
  update public.profiles set coin_balance = coin_balance + v_tx.coins_delta where id = v_tx.user_id;

  return jsonb_build_object('status', 'approved', 'coins_added', v_tx.coins_delta);
end;
$$;

-- 11. เปิด Row Level Security (RLS) เพื่อความปลอดภัยของข้อมูล
alter table public.profiles enable row level security;
alter table public.site_settings enable row level security;
alter table public.novels enable row level security;
alter table public.chapters enable row level security;
alter table public.unlocked_chapters enable row level security;
alter table public.bookmarks_progress enable row level security;
alter table public.transactions enable row level security;

-- Policies
create policy "Users view own profile" on public.profiles
  for select using (auth.uid() = id or public.is_admin());

create policy "Anyone can read site settings" on public.site_settings
  for select using (true);
create policy "Admin can update site settings" on public.site_settings
  for all using (public.is_admin());

create policy "Anyone can read novels" on public.novels
  for select using (true);
create policy "Admin manages novels" on public.novels
  for all using (public.is_admin());

create policy "Anyone can read chapter list & unlocked content" on public.chapters
  for select using (true);
create policy "Admin manages chapters" on public.chapters
  for all using (public.is_admin());

create policy "Users view own unlocks" on public.unlocked_chapters
  for select using (auth.uid() = user_id or public.is_admin());

create policy "Users manage own bookmarks" on public.bookmarks_progress
  for all using (auth.uid() = user_id);

create policy "Users view own transactions" on public.transactions
  for select using (auth.uid() = user_id or public.is_admin());
create policy "Users submit topup request" on public.transactions
  for insert with check (auth.uid() = user_id and type = 'topup' and status = 'pending');

-- 12. สร้าง Storage Buckets สำหรับอัปโหลดรูปปก แบนเนอร์ และสลิป
insert into storage.buckets (id, name, public) values ('media', 'media', true) on conflict do nothing;
insert into storage.buckets (id, name, public) values ('slips', 'slips', true) on conflict do nothing;

create policy "Public read media" on storage.objects
  for select using (bucket_id in ('media', 'slips'));
create policy "Admin upload media" on storage.objects
  for insert with check (bucket_id = 'media' and public.is_admin());
create policy "Users upload slips" on storage.objects
  for insert with check (bucket_id = 'slips' and auth.role() = 'authenticated');
