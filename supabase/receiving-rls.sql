begin;

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

create or replace function public.current_app_user_has_mobile_permission(target_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.role_mobile_permissions rmp
    where rmp.role_id = public.current_app_user_role_id()
      and rmp.permission_key = target_permission_key
  )
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

create or replace function public.current_app_user_can_receive_at_location(target_location_id int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or (
      public.current_app_user_has_mobile_permission('receiving')
      and target_location_id in (
        select location_id
        from public.current_app_user_location_ids()
      )
    )
$$;

create or replace function public.current_app_user_can_view_receiving_at_location(target_location_id int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or (
      (
        public.current_app_user_has_mobile_permission('receiving')
        or public.current_app_user_has_mobile_permission('view_receiving_history')
      )
      and target_location_id in (
        select location_id
        from public.current_app_user_location_ids()
      )
    )
$$;

revoke all on function public.current_app_user_id() from public;
revoke all on function public.current_app_user_role_id() from public;
revoke all on function public.current_app_user_is_admin() from public;
revoke all on function public.current_app_user_has_mobile_permission(text) from public;
revoke all on function public.current_app_user_location_ids() from public;
revoke all on function public.current_app_user_can_receive_at_location(int) from public;
revoke all on function public.current_app_user_can_view_receiving_at_location(int) from public;

grant execute on function public.current_app_user_id() to authenticated;
grant execute on function public.current_app_user_role_id() to authenticated;
grant execute on function public.current_app_user_is_admin() to authenticated;
grant execute on function public.current_app_user_has_mobile_permission(text) to authenticated;
grant execute on function public.current_app_user_location_ids() to authenticated;
grant execute on function public.current_app_user_can_receive_at_location(int) to authenticated;
grant execute on function public.current_app_user_can_view_receiving_at_location(int) to authenticated;

alter table public.receiving_batches enable row level security;
alter table public.inventory_movements enable row level security;

drop policy if exists "Users can read receiving batches for allowed stores" on public.receiving_batches;
drop policy if exists "Users can insert receiving batches for allowed stores" on public.receiving_batches;
drop policy if exists "Users can read receiving movements for allowed stores" on public.inventory_movements;
drop policy if exists "Users can insert receive movements for allowed stores" on public.inventory_movements;

create policy "Users can read receiving batches for allowed stores"
on public.receiving_batches
for select
to authenticated
using (public.current_app_user_can_view_receiving_at_location(location_id));

create policy "Users can insert receiving batches for allowed stores"
on public.receiving_batches
for insert
to authenticated
with check (
  user_id = public.current_app_user_id()
  and public.current_app_user_can_receive_at_location(location_id)
);

create policy "Users can read receiving movements for allowed stores"
on public.inventory_movements
for select
to authenticated
using (
  reason = 'receive'
  and public.current_app_user_can_view_receiving_at_location(location_id)
);

create policy "Users can insert receive movements for allowed stores"
on public.inventory_movements
for insert
to authenticated
with check (
  reason = 'receive'
  and public.current_app_user_can_receive_at_location(location_id)
);

commit;
