-- RLS policies for mobile device tracking.
--
-- Run this in the Supabase SQL Editor after the devices/device_sessions tables
-- exist. This allows authenticated mobile clients to register and update their
-- own device/session activity, while keeping approval/block controls admin-only.

begin;

alter table public.devices enable row level security;
alter table public.device_sessions enable row level security;

create or replace function public.device_is_owned_by_current_user(target_device_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.devices d
    where d.device_id = target_device_id
      and d.last_login_user_id = public.current_app_user_id()
  )
$$;

create or replace function public.device_flags_match_current(
  target_device_id uuid,
  approved boolean,
  blocked boolean
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.devices d
    where d.device_id = target_device_id
      and d.is_approved = approved
      and d.is_blocked = blocked
  )
$$;

create or replace function public.device_session_is_owned_by_current_user(target_session_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.device_sessions ds
    where ds.session_id = target_session_id
      and ds.user_id = public.current_app_user_id()
  )
$$;

revoke all on function public.device_is_owned_by_current_user(uuid) from public;
revoke all on function public.device_flags_match_current(uuid, boolean, boolean) from public;
revoke all on function public.device_session_is_owned_by_current_user(bigint) from public;
grant execute on function public.device_is_owned_by_current_user(uuid) to authenticated;
grant execute on function public.device_flags_match_current(uuid, boolean, boolean) to authenticated;
grant execute on function public.device_session_is_owned_by_current_user(bigint) to authenticated;

drop policy if exists "Users can read their own devices" on public.devices;
drop policy if exists "Users can register their own devices" on public.devices;
drop policy if exists "Users can update their own devices" on public.devices;
drop policy if exists "Admins can manage all devices" on public.devices;

drop policy if exists "Users can read their own device sessions" on public.device_sessions;
drop policy if exists "Users can insert their own device sessions" on public.device_sessions;
drop policy if exists "Users can update their own device sessions" on public.device_sessions;
drop policy if exists "Admins can manage all device sessions" on public.device_sessions;

create policy "Users can read their own devices"
on public.devices
for select
to authenticated
using (
  public.current_app_user_is_admin()
  or last_login_user_id = public.current_app_user_id()
);

create policy "Users can register their own devices"
on public.devices
for insert
to authenticated
with check (
  last_login_user_id = public.current_app_user_id()
  and coalesce(is_approved, false) = false
  and coalesce(is_blocked, false) = false
);

create policy "Users can update their own devices"
on public.devices
for update
to authenticated
using (
  public.current_app_user_is_admin()
  or public.device_is_owned_by_current_user(device_id)
)
with check (
  public.current_app_user_is_admin()
  or (
    last_login_user_id = public.current_app_user_id()
    and public.device_flags_match_current(device_id, is_approved, is_blocked)
  )
);

create policy "Admins can manage all devices"
on public.devices
for all
to authenticated
using (public.current_app_user_is_admin())
with check (public.current_app_user_is_admin());

create policy "Users can read their own device sessions"
on public.device_sessions
for select
to authenticated
using (
  public.current_app_user_is_admin()
  or user_id = public.current_app_user_id()
);

create policy "Users can insert their own device sessions"
on public.device_sessions
for insert
to authenticated
with check (
  user_id = public.current_app_user_id()
  and public.device_is_owned_by_current_user(device_id)
);

create policy "Users can update their own device sessions"
on public.device_sessions
for update
to authenticated
using (
  public.current_app_user_is_admin()
  or public.device_session_is_owned_by_current_user(session_id)
)
with check (
  public.current_app_user_is_admin()
  or (
    user_id = public.current_app_user_id()
    and public.device_is_owned_by_current_user(device_id)
  )
);

create policy "Admins can manage all device sessions"
on public.device_sessions
for all
to authenticated
using (public.current_app_user_is_admin())
with check (public.current_app_user_is_admin());

commit;
