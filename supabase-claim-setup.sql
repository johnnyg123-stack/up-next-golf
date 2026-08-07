-- ============================================================
-- Up Next Golf — CLAIM model (private code + email OTP)
-- Run in Supabase → SQL Editor → New query → paste all → Run.
-- WARNING: this rebuilds the tables and CLEARS existing test data.
-- ============================================================

drop table if exists public.tournaments  cascade;
drop table if exists public.claim_codes   cascade;
drop table if exists public.profiles       cascade;
drop table if exists public.admin_emails   cascade;

-- ---------- Admin allowlist (by email) ----------
create table public.admin_emails ( email text primary key );
-- >>> Change this to your admin email if different <<<
insert into public.admin_emails(email) values ('hudsonwilt@icloud.com');

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admin_emails
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- ---------- Roster profiles ----------
create table public.profiles (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  hometown    text,
  grad_year   int,
  commitment  text,
  height      text,
  weight      text,
  claimed_by  uuid references auth.users(id) on delete set null,  -- null = unclaimed
  claimed_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index profiles_claimed_by_idx on public.profiles (claimed_by);
create index profiles_name_idx       on public.profiles (lower(name));

-- ---------- Private claim codes (NEVER exposed to the public) ----------
create table public.claim_codes (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  code       text not null
);

-- ---------- Tournaments ----------
create table public.tournaments (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  name        text not null,
  date        date,
  location    text,
  result      text,
  created_at  timestamptz not null default now()
);
create index tournaments_profile_id_idx on public.tournaments (profile_id);

-- ============================================================
-- Row-Level Security
-- ============================================================
alter table public.profiles     enable row level security;
alter table public.claim_codes  enable row level security;
alter table public.tournaments  enable row level security;
alter table public.admin_emails enable row level security;

-- profiles: public sees CLAIMED only; owner sees own; admin sees all
create policy profiles_read on public.profiles
  for select using (claimed_by is not null or claimed_by = auth.uid() or public.is_admin());
create policy profiles_update_owner on public.profiles
  for update using (claimed_by = auth.uid() or public.is_admin())
             with check (claimed_by = auth.uid() or public.is_admin());
create policy profiles_admin_insert on public.profiles
  for insert with check (public.is_admin());
create policy profiles_admin_delete on public.profiles
  for delete using (public.is_admin());

-- claim_codes: ONLY admin can read/write (codes stay secret)
create policy claim_codes_admin_all on public.claim_codes
  for all using (public.is_admin()) with check (public.is_admin());

-- tournaments: public read; only the profile's claimer manages its rows
create policy tournaments_read on public.tournaments
  for select using (true);
create policy tournaments_owner_ins on public.tournaments
  for insert with check (exists (select 1 from public.profiles p where p.id = profile_id and p.claimed_by = auth.uid()));
create policy tournaments_owner_upd on public.tournaments
  for update using (exists (select 1 from public.profiles p where p.id = profile_id and p.claimed_by = auth.uid()));
create policy tournaments_owner_del on public.tournaments
  for delete using (exists (select 1 from public.profiles p where p.id = profile_id and p.claimed_by = auth.uid()));

-- admin_emails: readable only by admins
create policy admin_emails_admin_read on public.admin_emails
  for select using (public.is_admin());

-- ============================================================
-- Functions the app calls (RPC)
-- ============================================================

-- Search UNCLAIMED profiles by name (for the claim flow). Returns no codes.
create or replace function public.find_claimable(q text)
returns table (id uuid, name text, grad_year int)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.grad_year
  from public.profiles p
  where p.claimed_by is null
    and length(coalesce(q, '')) >= 2
    and p.name ilike '%' || q || '%'
  order by p.name
  limit 15;
$$;

-- Claim a profile: caller must be signed in (via email OTP) AND provide the right code.
create or replace function public.claim_profile(p_profile_id uuid, p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'Please verify your email first.');
  end if;
  if exists (select 1 from public.profiles where id = p_profile_id and claimed_by is not null) then
    return json_build_object('ok', false, 'error', 'This profile has already been claimed.');
  end if;
  if not exists (
        select 1 from public.claim_codes
        where profile_id = p_profile_id
          and upper(trim(code)) = upper(trim(coalesce(p_code, '')))
     ) then
    return json_build_object('ok', false, 'error', 'That claim code is not correct.');
  end if;
  update public.profiles
     set claimed_by = v_uid, claimed_at = now(), updated_at = now()
   where id = p_profile_id and claimed_by is null;
  return json_build_object('ok', true, 'id', p_profile_id);
end $$;

-- Admin: add a golfer, returns the generated claim code
create or replace function public.admin_add_golfer(p_name text, p_grad_year int default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_code text;
begin
  if not public.is_admin() then
    return json_build_object('ok', false, 'error', 'Not authorized.');
  end if;
  if coalesce(trim(p_name), '') = '' then
    return json_build_object('ok', false, 'error', 'Name is required.');
  end if;
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  insert into public.profiles(name, grad_year) values (trim(p_name), p_grad_year) returning id into v_id;
  insert into public.claim_codes(profile_id, code) values (v_id, v_code);
  return json_build_object('ok', true, 'id', v_id, 'code', v_code);
end $$;
