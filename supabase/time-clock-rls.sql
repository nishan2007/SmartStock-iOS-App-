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

revoke all on function public.current_app_user_id() from public;
revoke all on function public.current_app_user_role_id() from public;
revoke all on function public.current_app_user_is_admin() from public;
revoke all on function public.current_app_user_has_mobile_permission(text) from public;

grant execute on function public.current_app_user_id() to authenticated;
grant execute on function public.current_app_user_role_id() to authenticated;
grant execute on function public.current_app_user_is_admin() to authenticated;
grant execute on function public.current_app_user_has_mobile_permission(text) to authenticated;

alter table public.employee_time_clock enable row level security;

drop policy if exists "Users can read their own time clock entries" on public.employee_time_clock;
drop policy if exists "Users can insert their own time clock entries" on public.employee_time_clock;
drop policy if exists "Users can update their own open time clock entries" on public.employee_time_clock;

create policy "Users can read their own time clock entries"
on public.employee_time_clock
for select
to authenticated
using (
  public.current_app_user_is_admin()
  or (
    public.current_app_user_has_mobile_permission('time_clock')
    and user_id = public.current_app_user_id()
  )
);

create policy "Users can insert their own time clock entries"
on public.employee_time_clock
for insert
to authenticated
with check (
  user_id = public.current_app_user_id()
  and (
    public.current_app_user_is_admin()
    or public.current_app_user_has_mobile_permission('time_clock')
  )
);

create policy "Users can update their own open time clock entries"
on public.employee_time_clock
for update
to authenticated
using (
  user_id = public.current_app_user_id()
  and (
    public.current_app_user_is_admin()
    or public.current_app_user_has_mobile_permission('time_clock')
  )
)
with check (
  user_id = public.current_app_user_id()
  and (
    public.current_app_user_is_admin()
    or public.current_app_user_has_mobile_permission('time_clock')
  )
);

commit;
