-- ============================================================
-- Up Next Golf — OPEN submissions (create a profile with NO login)
-- Run in Supabase → SQL Editor. Safe to re-run. No data wiped.
-- ============================================================

-- Store the email someone submits with (so they can edit later if they sign in)
alter table public.profiles add column if not exists submit_email text;

-- Approved profiles are public even if nobody has "claimed"/signed-in for them
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select using (status = 'approved' or claimed_by = auth.uid() or public.is_admin());

-- Anyone (no login) can submit a profile for approval
create or replace function public.submit_profile(
  p_name text, p_email text, p_hometown text default null, p_grad_year int default null,
  p_commitment text default null, p_height text default null, p_weight text default null
) returns json language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if coalesce(trim(p_name), '') = '' then
    return json_build_object('ok', false, 'error', 'Please enter your name.');
  end if;
  if coalesce(trim(p_email), '') = '' or position('@' in p_email) = 0 then
    return json_build_object('ok', false, 'error', 'Please enter a valid email.');
  end if;
  if exists (select 1 from public.profiles
             where lower(submit_email) = lower(trim(p_email))
               and claimed_by is null and status <> 'rejected') then
    return json_build_object('ok', false, 'error', 'A profile with that email is already submitted.');
  end if;
  insert into public.profiles(name, hometown, grad_year, commitment, height, weight, submit_email, status, claimed_by)
    values (trim(p_name), nullif(trim(p_hometown), ''), p_grad_year, nullif(trim(p_commitment), ''),
            nullif(trim(p_height), ''), nullif(trim(p_weight), ''), lower(trim(p_email)), 'pending', null)
    returning id into v_id;
  return json_build_object('ok', true, 'id', v_id);
end $$;

-- If a golfer later signs in with the email they submitted, link that profile to them so they can edit it
create or replace function public.claim_my_submission()
returns json language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text := lower(coalesce(auth.jwt() ->> 'email', '')); v_id uuid;
begin
  if v_uid is null then return json_build_object('ok', false); end if;
  if exists (select 1 from public.profiles where claimed_by = v_uid) then
    return json_build_object('ok', true, 'already', true);
  end if;
  select id into v_id from public.profiles
    where claimed_by is null and lower(submit_email) = v_email
    order by created_at limit 1;
  if v_id is null then return json_build_object('ok', false); end if;
  update public.profiles set claimed_by = v_uid where id = v_id and claimed_by is null;
  return json_build_object('ok', true, 'id', v_id);
end $$;
