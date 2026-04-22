-- Fix: "infinite recursion detected in policy for relation users"
--
-- Run this in the Supabase SQL Editor.
--
-- Why this happens:
-- A policy on public.users probably queries public.users again, for example:
--   exists (select 1 from public.users where auth_user_id = auth.uid() and role_id = 1)
-- Since that query also has to pass the public.users policies, Postgres keeps
-- re-entering the same policy until it aborts with infinite recursion.
--
-- This script moves those lookups into SECURITY DEFINER helpers, then uses the
-- helpers from RLS policies.

begin;

alter table public.users enable row level security;
alter table public.product_barcodes enable row level security;

create or replace function public.current_app_user_id()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select u.user_id
  from public.users u
  where u.auth_user_id = auth.uid()
  limit 1
$$;

create or replace function public.current_app_user_role_id()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select u.role_id
  from public.users u
  where u.auth_user_id = auth.uid()
  limit 1
$$;

create or replace function public.current_app_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_app_user_role_id() = 1, false)
$$;

create or replace function public.current_app_user_location_ids()
returns table (location_id int)
language sql
stable
security definer
set search_path = public
as $$
  select ul.location_id
  from public.user_locations ul
  join public.users u on u.user_id = ul.user_id
  where u.auth_user_id = auth.uid()
$$;

create or replace function public.can_read_app_user(
  target_user_id int,
  target_auth_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    target_auth_user_id = auth.uid()
    or coalesce(public.current_app_user_is_admin(), false)
    or exists (
      select 1
      from public.user_locations me_ul
      join public.users me on me.user_id = me_ul.user_id
      join public.user_locations coworker_ul
        on coworker_ul.location_id = me_ul.location_id
      where me.auth_user_id = auth.uid()
        and coworker_ul.user_id = target_user_id
    )
$$;

revoke all on function public.current_app_user_id() from public;
revoke all on function public.current_app_user_role_id() from public;
revoke all on function public.current_app_user_is_admin() from public;
revoke all on function public.current_app_user_location_ids() from public;
revoke all on function public.can_read_app_user(int, uuid) from public;
grant execute on function public.current_app_user_id() to authenticated;
grant execute on function public.current_app_user_role_id() to authenticated;
grant execute on function public.current_app_user_is_admin() to authenticated;
grant execute on function public.current_app_user_location_ids() to authenticated;
grant execute on function public.can_read_app_user(int, uuid) to authenticated;

create or replace function public.lookup_login_user(identifier text)
returns table (
  email text,
  auth_user_id uuid,
  is_active boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select u.email, u.auth_user_id, u.is_active
  from public.users u
  where u.is_active = true
    and (
      lower(u.username) = lower(identifier)
      or lower(u.email) = lower(identifier)
    )
  limit 1
$$;

revoke all on function public.lookup_login_user(text) from public;
grant execute on function public.lookup_login_user(text) to anon;
grant execute on function public.lookup_login_user(text) to authenticated;

-- Replace these names with the policy names shown in your Supabase dashboard if
-- yours differ. DROP POLICY IF EXISTS is safe when a name does not exist.
drop policy if exists "Users can read own profile" on public.users;
drop policy if exists "Users can read their own profile" on public.users;
drop policy if exists "Admins can read users" on public.users;
drop policy if exists "Admins can insert users" on public.users;
drop policy if exists "Admins can update users" on public.users;
drop policy if exists "Admins can delete users" on public.users;
drop policy if exists "Users can read coworkers at assigned stores" on public.users;
drop policy if exists "Users can read product barcodes at assigned stores" on public.product_barcodes;

-- Authenticated users can load their own SmartStock profile after Supabase Auth
-- login. Admin users can manage employees.
create policy "Users can read their own profile"
on public.users
for select
to authenticated
using (public.can_read_app_user(user_id, auth_user_id));

create policy "Admins can insert users"
on public.users
for insert
to authenticated
with check (public.current_app_user_is_admin());

create policy "Admins can update users"
on public.users
for update
to authenticated
using (public.current_app_user_is_admin())
with check (public.current_app_user_is_admin());

create policy "Admins can delete users"
on public.users
for delete
to authenticated
using (public.current_app_user_is_admin());

create policy "Users can read product barcodes at assigned stores"
on public.product_barcodes
for select
to authenticated
using (
  public.current_app_user_is_admin()
  or exists (
    select 1
    from public.inventory i
    where i.product_id = product_barcodes.product_id
      and i.location_id in (
        select location_id from public.current_app_user_location_ids()
      )
  )
);

commit;

-- If your table is actually named public."user" instead of public.users,
-- replace every "public.users" above with "public.""user""" before running it.
