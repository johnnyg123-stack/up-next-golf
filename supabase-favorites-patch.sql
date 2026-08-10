-- ============================================================
-- Up Next Golf — favorites (star a golfer)
-- Run in Supabase → SQL Editor. Safe to re-run. No data wiped.
-- ============================================================
create table if not exists public.favorites (
  user_id    uuid not null references auth.users(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, profile_id)
);

alter table public.favorites enable row level security;

-- Each user can see and manage ONLY their own favorites
drop policy if exists favorites_select_own on public.favorites;
create policy favorites_select_own on public.favorites
  for select using (user_id = auth.uid());

drop policy if exists favorites_insert_own on public.favorites;
create policy favorites_insert_own on public.favorites
  for insert with check (user_id = auth.uid());

drop policy if exists favorites_delete_own on public.favorites;
create policy favorites_delete_own on public.favorites
  for delete using (user_id = auth.uid());
