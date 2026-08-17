-- ============================================================
-- Up Next Golf — profile pictures (Supabase Storage)
-- Run in Supabase → SQL Editor. Safe to re-run. No data wiped.
-- ============================================================

-- 1) Column to hold each profile's photo URL
alter table public.profiles add column if not exists avatar_url text;

-- 2) Public storage bucket for photos (3 MB max, images only)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 3145728, array['image/png','image/jpeg','image/webp','image/gif'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 3) Anyone can view photos; anyone can upload to the avatars bucket
--    (size + type limits above, and admin approval gates what shows publicly)
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists avatars_insert on storage.objects;
create policy avatars_insert on storage.objects
  for insert with check (bucket_id = 'avatars');

-- 4) submit_profile now also accepts a photo URL
drop function if exists public.submit_profile(text, text, text, int, text, text, text);
create or replace function public.submit_profile(
  p_name text, p_email text, p_hometown text default null, p_grad_year int default null,
  p_commitment text default null, p_height text default null, p_weight text default null,
  p_avatar_url text default null
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
  insert into public.profiles(name, hometown, grad_year, commitment, height, weight, submit_email, avatar_url, status, claimed_by)
    values (trim(p_name), nullif(trim(p_hometown), ''), p_grad_year, nullif(trim(p_commitment), ''),
            nullif(trim(p_height), ''), nullif(trim(p_weight), ''), lower(trim(p_email)),
            nullif(trim(p_avatar_url), ''), 'pending', null)
    returning id into v_id;
  return json_build_object('ok', true, 'id', v_id);
end $$;
