-- RLS policies for customer_accounts used by the SmartStock iOS app.
--
-- Run this in the Supabase SQL Editor. Without a select policy, authenticated
-- mobile users can hit the endpoint successfully and still receive [].

begin;

alter table public.customer_accounts enable row level security;

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

create or replace function public.customer_account_manage_fields_unchanged(
  target_customer_id int,
  target_name text,
  target_phone text,
  target_email text,
  target_is_active boolean,
  target_is_business boolean,
  target_account_notes text,
  target_customer_type_id int,
  target_created_at timestamptz,
  target_current_balance numeric
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.customer_accounts c
    where c.customer_id = target_customer_id
      and c.name is not distinct from target_name
      and c.phone is not distinct from target_phone
      and c.email is not distinct from target_email
      and c.is_active is not distinct from target_is_active
      and c.is_business is not distinct from target_is_business
      and c.account_notes is not distinct from target_account_notes
      and c.customer_type_id is not distinct from target_customer_type_id
      and c.created_at is not distinct from target_created_at
      and c.current_balance is not distinct from target_current_balance
  )
$$;

create or replace function public.customer_account_account_number_unchanged(
  target_customer_id int,
  target_account_number text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.customer_accounts c
    where c.customer_id = target_customer_id
      and c.account_number is not distinct from target_account_number
  )
$$;

create or replace function public.customer_account_credit_limit_unchanged(
  target_customer_id int,
  target_credit_limit numeric
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.customer_accounts c
    where c.customer_id = target_customer_id
      and c.credit_limit is not distinct from target_credit_limit
  )
$$;

revoke all on function public.current_app_user_id() from public;
revoke all on function public.current_app_user_role_id() from public;
revoke all on function public.current_app_user_is_admin() from public;
revoke all on function public.current_app_user_has_mobile_permission(text) from public;
revoke all on function public.customer_account_manage_fields_unchanged(int, text, text, text, boolean, boolean, text, int, timestamptz, numeric) from public;
revoke all on function public.customer_account_account_number_unchanged(int, text) from public;
revoke all on function public.customer_account_credit_limit_unchanged(int, numeric) from public;
grant execute on function public.current_app_user_id() to authenticated;
grant execute on function public.current_app_user_role_id() to authenticated;
grant execute on function public.current_app_user_is_admin() to authenticated;
grant execute on function public.current_app_user_has_mobile_permission(text) to authenticated;
grant execute on function public.customer_account_manage_fields_unchanged(int, text, text, text, boolean, boolean, text, int, timestamptz, numeric) to authenticated;
grant execute on function public.customer_account_account_number_unchanged(int, text) to authenticated;
grant execute on function public.customer_account_credit_limit_unchanged(int, numeric) to authenticated;

drop policy if exists "Authenticated users can read customers" on public.customer_accounts;
drop policy if exists "Authenticated users can create customers" on public.customer_accounts;
drop policy if exists "Admins can update customers" on public.customer_accounts;
drop policy if exists "Admins can delete customers" on public.customer_accounts;

create policy "Authenticated users can read customers"
on public.customer_accounts
for select
to authenticated
using (
  public.current_app_user_has_mobile_permission('customers')
  or public.current_app_user_has_mobile_permission('manage_customers')
);

create policy "Authenticated users can create customers"
on public.customer_accounts
for insert
to authenticated
with check (public.current_app_user_has_mobile_permission('manage_customers'));

create policy "Admins can update customers"
on public.customer_accounts
for update
to authenticated
using (
  public.current_app_user_has_mobile_permission('manage_customers')
  or public.current_app_user_has_mobile_permission('edit_customer_credit_limit')
  or public.current_app_user_has_mobile_permission('edit_account_number')
)
with check (
  (
    public.current_app_user_has_mobile_permission('manage_customers')
    or public.customer_account_manage_fields_unchanged(
      customer_id,
      name,
      phone,
      email,
      is_active,
      is_business,
      account_notes,
      customer_type_id,
      created_at,
      current_balance
    )
  )
  and (
    public.current_app_user_has_mobile_permission('edit_account_number')
    or public.customer_account_account_number_unchanged(customer_id, account_number)
  )
  and (
    public.current_app_user_has_mobile_permission('edit_customer_credit_limit')
    or public.customer_account_credit_limit_unchanged(customer_id, credit_limit)
  )
);

create policy "Admins can delete customers"
on public.customer_accounts
for delete
to authenticated
using (public.current_app_user_has_mobile_permission('manage_customers'));

commit;
