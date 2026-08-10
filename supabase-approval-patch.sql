-- ============================================================
-- Up Next Golf — add SELF-SIGNUP + ADMIN APPROVAL
-- Run in Supabase → SQL Editor. Safe to re-run. Does NOT wipe data.
-- ============================================================

-- 1) Approval status on each profile
alter table public.profiles add column if not exists status text not null default 'pending';

-- Anything already claimed becomes 'approved' so it isn't suddenly hidden
update public.profiles set status = 'approved' where claimed_by is not null and status = 'pending';

-- 2) One profile per signed-in person (stops spam of multiple profiles)
create unique index if not exists one_profile_per_user
  on public.profiles(claimed_by) where claimed_by is not null;

-- 3) Golfers can NEVER set/change their own status (only admins can approve)
create or replace function public.protect_profile_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    if TG_OP = 'INSERT' then NEW.status := 'pending'; end if;
    if TG_OP = 'UPDATE' then NEW.status := OLD.status; end if;
  end if;
  return NEW;
end $$;
drop trigger if exists trg_protect_status on public.profiles;
create trigger trg_protect_status before insert or update on public.profiles
  for each row execute function public.protect_profile_status();

-- 4) Public directory shows only APPROVED + claimed; owner sees own; admin sees all
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select using (
    (status = 'approved' and claimed_by is not null)
    or claimed_by = auth.uid()
    or public.is_admin()
  );

-- 5) A signed-in golfer may create THEIR OWN profile (status forced to pending by the trigger)
drop policy if exists profiles_self_insert on public.profiles;
create policy profiles_self_insert on public.profiles
  for insert with check (claimed_by = auth.uid());

-- 6) Admin-added roster golfers are auto-approved (admin vouches for them)
create or replace function public.admin_add_golfer(p_name text, p_grad_year int default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_code text;
begin
  if not public.is_admin() then return json_build_object('ok', false, 'error', 'Not authorized.'); end if;
  if coalesce(trim(p_name), '') = '' then return json_build_object('ok', false, 'error', 'Name is required.'); end if;
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  insert into public.profiles(name, grad_year, status) values (trim(p_name), p_grad_year, 'approved') returning id into v_id;
  insert into public.claim_codes(profile_id, code) values (v_id, v_code);
  return json_build_object('ok', true, 'id', v_id, 'code', v_code);
end $$;
