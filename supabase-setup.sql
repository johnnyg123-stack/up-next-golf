-- ============================================================
-- Junior Golf — database setup
-- Run ONCE in Supabase:  Dashboard → SQL Editor → New query
-- Paste all of this → click "Run".  Safe to re-run.
-- ============================================================

-- 1) PROFILES — one row per signed-in user (id = their auth user id)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null,
  hometown    text,
  grad_year   int,
  commitment  text,
  height      text,
  weight      text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2) TOURNAMENTS — schedule rows owned by a profile (profile_id = owner's user id)
create table if not exists public.tournaments (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  name        text not null,
  date        date,
  location    text,
  result      text,
  created_at  timestamptz not null default now()
);
create index if not exists tournaments_profile_id_idx on public.tournaments(profile_id);

-- 3) ROW-LEVEL SECURITY — the rules that keep each kid's data theirs
alter table public.profiles    enable row level security;
alter table public.tournaments enable row level security;

-- Profiles: anyone may READ the directory; you may only write your OWN row
drop policy if exists profiles_public_read on public.profiles;
create policy profiles_public_read on public.profiles
  for select using (true);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists profiles_delete_own on public.profiles;
create policy profiles_delete_own on public.profiles
  for delete using (auth.uid() = id);

-- Tournaments: anyone may READ; you may only write your OWN rows
drop policy if exists tournaments_public_read on public.tournaments;
create policy tournaments_public_read on public.tournaments
  for select using (true);

drop policy if exists tournaments_insert_own on public.tournaments;
create policy tournaments_insert_own on public.tournaments
  for insert with check (auth.uid() = profile_id);

drop policy if exists tournaments_update_own on public.tournaments;
create policy tournaments_update_own on public.tournaments
  for update using (auth.uid() = profile_id) with check (auth.uid() = profile_id);

drop policy if exists tournaments_delete_own on public.tournaments;
create policy tournaments_delete_own on public.tournaments
  for delete using (auth.uid() = profile_id);
