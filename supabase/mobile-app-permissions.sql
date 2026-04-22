-- Mobile-only permissions for the SmartStock iOS app.
--
-- This is intentionally separate from any Java/desktop app permission tables.
-- Run in the Supabase SQL Editor.

begin;

create table if not exists public.mobile_permissions (
  permission_key text primary key,
  display_name text not null,
  permission_group text not null,
  sort_order int not null default 0
);

create table if not exists public.role_mobile_permissions (
  role_id int not null references public.roles(role_id) on delete cascade,
  permission_key text not null references public.mobile_permissions(permission_key) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_key)
);

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

revoke all on function public.current_app_user_role_id() from public;
revoke all on function public.current_app_user_is_admin() from public;
grant execute on function public.current_app_user_role_id() to authenticated;
grant execute on function public.current_app_user_is_admin() to authenticated;

insert into public.mobile_permissions (permission_key, display_name, permission_group, sort_order)
values
  ('make_sale', 'Make Sale', 'Sales', 10),
  ('view_sales', 'View Sales', 'Sales', 20),
  ('returns', 'Returns', 'Sales', 30),
  ('end_of_day', 'End of Day', 'Sales', 40),
  ('customers', 'Customers', 'Sales', 50),
  ('inventory', 'Inventory', 'Inventory', 100),
  ('receiving', 'Receiving', 'Inventory', 110),
  ('store_transfer', 'Store Transfer', 'Inventory', 120),
  ('edit_item', 'Edit Item', 'Inventory', 130),
  ('new_item', 'New Item', 'Inventory', 140),
  ('time_clock', 'Time Clock', 'Employee', 200),
  ('employees', 'Employees', 'Admin', 300),
  ('role_permissions', 'Role Permissions', 'Admin', 310)
on conflict (permission_key) do update
set
  display_name = excluded.display_name,
  permission_group = excluded.permission_group,
  sort_order = excluded.sort_order;

-- Admin role gets every mobile permission by default.
insert into public.role_mobile_permissions (role_id, permission_key)
select 1, permission_key
from public.mobile_permissions
on conflict (role_id, permission_key) do nothing;

alter table public.mobile_permissions enable row level security;
alter table public.role_mobile_permissions enable row level security;

drop policy if exists "Authenticated users can read mobile permissions" on public.mobile_permissions;
drop policy if exists "Users can read their role mobile permissions" on public.role_mobile_permissions;
drop policy if exists "Admins can read all role mobile permissions" on public.role_mobile_permissions;
drop policy if exists "Admins can insert role mobile permissions" on public.role_mobile_permissions;
drop policy if exists "Admins can delete role mobile permissions" on public.role_mobile_permissions;

create policy "Authenticated users can read mobile permissions"
on public.mobile_permissions
for select
to authenticated
using (true);

create policy "Users can read their role mobile permissions"
on public.role_mobile_permissions
for select
to authenticated
using (role_id = public.current_app_user_role_id());

create policy "Admins can read all role mobile permissions"
on public.role_mobile_permissions
for select
to authenticated
using (public.current_app_user_is_admin());

create policy "Admins can insert role mobile permissions"
on public.role_mobile_permissions
for insert
to authenticated
with check (public.current_app_user_is_admin());

create policy "Admins can delete role mobile permissions"
on public.role_mobile_permissions
for delete
to authenticated
using (public.current_app_user_is_admin());

commit;
