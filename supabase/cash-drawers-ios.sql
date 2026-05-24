-- Cash drawer support for the SmartStock iOS app.
-- Run in the Supabase SQL Editor after mobile-app-permissions.sql.

begin;

insert into public.mobile_permissions (permission_key, display_name, permission_group, sort_order)
values ('cash_drawer_management', 'Cash Drawer Management', 'Device', 306)
on conflict (permission_key) do update
set display_name = excluded.display_name,
    permission_group = excluded.permission_group,
    sort_order = excluded.sort_order;

insert into public.role_mobile_permissions (role_id, permission_key)
select 1, 'cash_drawer_management'
where exists (select 1 from public.roles where role_id = 1)
on conflict (role_id, permission_key) do nothing;

create table if not exists public.cash_drawers (
  drawer_id bigserial primary key,
  store_id int not null references public.locations(location_id) on delete cascade,
  drawer_name text not null,
  drawer_code text null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.cash_drawer_device_assignments (
  assignment_id bigserial primary key,
  store_id int not null references public.locations(location_id) on delete cascade,
  drawer_id bigint not null references public.cash_drawers(drawer_id) on delete cascade,
  device_id uuid not null references public.devices(device_id) on delete cascade,
  notes text null,
  is_active boolean not null default true,
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz null
);

alter table public.cash_drawer_device_assignments
add column if not exists notes text null;

alter table public.locations
add column if not exists timezone text not null default 'America/New_York';

create index if not exists idx_cash_drawers_store_active
on public.cash_drawers (store_id, is_active, drawer_name);

create unique index if not exists idx_cash_drawers_store_code_unique
on public.cash_drawers (store_id, lower(drawer_code))
where drawer_code is not null and btrim(drawer_code) <> '';

create index if not exists idx_cash_drawer_assignments_store_drawer
on public.cash_drawer_device_assignments (store_id, drawer_id);

create unique index if not exists idx_cash_drawer_assignments_one_active_device
on public.cash_drawer_device_assignments (store_id, device_id)
where is_active;

alter table public.sales
add column if not exists cash_drawer_id bigint null references public.cash_drawers(drawer_id),
add column if not exists cash_drawer_name text null;

alter table public.custom_orders
add column if not exists cash_drawer_id bigint null references public.cash_drawers(drawer_id),
add column if not exists cash_drawer_name text null;

alter table public.custom_order_payments
add column if not exists cash_drawer_id bigint null references public.cash_drawers(drawer_id),
add column if not exists cash_drawer_name text null;

alter table public.custom_order_line_returns
add column if not exists cash_drawer_id bigint null references public.cash_drawers(drawer_id),
add column if not exists cash_drawer_name text null;

alter table public.customer_account_transactions
add column if not exists payment_method text null,
add column if not exists payment_reference text null,
add column if not exists cash_drawer_id bigint null references public.cash_drawers(drawer_id),
add column if not exists cash_drawer_name text null;

create index if not exists idx_sales_cash_drawer_created
on public.sales (cash_drawer_id, created_at desc);

create index if not exists idx_custom_order_payments_cash_drawer_created
on public.custom_order_payments (cash_drawer_id, created_at desc);

create index if not exists idx_customer_transactions_cash_drawer_created
on public.customer_account_transactions (cash_drawer_id, created_at desc);

create or replace function public.current_app_user_can_use_cash_drawers(target_store_id int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.current_app_user_has_location(target_store_id)
    and (
      coalesce(public.current_app_user_is_admin(), false)
      or public.current_app_user_has_mobile_permission('cash_drawer_management')
      or public.current_app_user_has_mobile_permission('make_sale')
      or public.current_app_user_has_mobile_permission('end_of_day')
      or public.current_app_user_has_mobile_permission('create_custom_order')
      or public.current_app_user_has_mobile_permission('manage_custom_orders')
      or public.current_app_user_has_mobile_permission('orders_end_of_day')
      or public.current_app_user_has_mobile_permission('manage_customers')
    )
$$;

revoke all on function public.current_app_user_can_use_cash_drawers(int) from public;
grant execute on function public.current_app_user_can_use_cash_drawers(int) to authenticated;

alter table public.cash_drawers enable row level security;
alter table public.cash_drawer_device_assignments enable row level security;

drop policy if exists "Users can read cash drawers" on public.cash_drawers;
drop policy if exists "Managers can insert cash drawers" on public.cash_drawers;
drop policy if exists "Managers can update cash drawers" on public.cash_drawers;
drop policy if exists "Users can read cash drawer assignments" on public.cash_drawer_device_assignments;
drop policy if exists "Managers can insert cash drawer assignments" on public.cash_drawer_device_assignments;
drop policy if exists "Managers can update cash drawer assignments" on public.cash_drawer_device_assignments;

create policy "Users can read cash drawers"
on public.cash_drawers
for select
to authenticated
using (public.current_app_user_can_use_cash_drawers(store_id));

create policy "Managers can insert cash drawers"
on public.cash_drawers
for insert
to authenticated
with check (
  public.current_app_user_has_location(store_id)
  and (
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('cash_drawer_management')
  )
);

create policy "Managers can update cash drawers"
on public.cash_drawers
for update
to authenticated
using (
  public.current_app_user_has_location(store_id)
  and (
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('cash_drawer_management')
  )
)
with check (
  public.current_app_user_has_location(store_id)
  and (
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('cash_drawer_management')
  )
);

create policy "Users can read cash drawer assignments"
on public.cash_drawer_device_assignments
for select
to authenticated
using (public.current_app_user_can_use_cash_drawers(store_id));

create policy "Managers can insert cash drawer assignments"
on public.cash_drawer_device_assignments
for insert
to authenticated
with check (
  public.current_app_user_has_location(store_id)
  and (
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('cash_drawer_management')
  )
);

create policy "Managers can update cash drawer assignments"
on public.cash_drawer_device_assignments
for update
to authenticated
using (
  public.current_app_user_has_location(store_id)
  and (
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('cash_drawer_management')
  )
)
with check (
  public.current_app_user_has_location(store_id)
  and (
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('cash_drawer_management')
  )
);

create or replace function public.record_customer_account_payment(
  target_customer_id int,
  target_amount numeric(12, 2),
  target_note text default null,
  target_user_name text default null,
  target_location_id int default null,
  target_payment_method text default null,
  target_payment_reference text default null,
  target_cash_drawer_id bigint default null,
  target_cash_drawer_name text default null
)
returns table (
  payment_transaction_id int,
  payment_id text,
  applied_note text,
  new_balance numeric(12, 2)
)
language plpgsql
security definer
set search_path = public
as $$
declare
  customer_row record;
  sale_row record;
  payment_transaction_id_local int;
  payment_id_local text;
  remaining_payment numeric(12, 2);
  applied_amount numeric(12, 2);
  sale_total numeric(12, 2);
  new_amount_paid numeric(12, 2);
  applied_parts text[] := '{}';
  combined_note text;
  normalized_method text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.current_app_user_can_record_customer_payments() then
    raise exception 'You do not have permission to record customer payments.';
  end if;

  if target_location_id is not null and not public.current_app_user_has_location(target_location_id) then
    raise exception 'You do not have access to this store.';
  end if;

  if target_amount is null or target_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  normalized_method := upper(coalesce(nullif(btrim(target_payment_method), ''), 'CASH'));

  if normalized_method = 'CASH' and target_cash_drawer_id is null then
    raise exception 'No cash drawer assigned to this device for this store.';
  end if;

  select
    customer_id,
    coalesce(current_balance, 0)::numeric(12, 2) as current_balance,
    coalesce(credit_limit, 0)::numeric(12, 2) as credit_limit,
    coalesce(is_active, true) as is_active
  into customer_row
  from public.customer_accounts
  where customer_id = target_customer_id
  for update;

  if not found then
    raise exception 'Customer account was not found.';
  end if;

  if not customer_row.is_active then
    raise exception 'Customer account is inactive.';
  end if;

  if customer_row.current_balance < target_amount then
    raise exception 'Payment is more than the current balance.';
  end if;

  update public.customer_accounts
  set current_balance = current_balance - target_amount
  where customer_id = target_customer_id;

  remaining_payment := target_amount;

  insert into public.customer_account_transactions (
    customer_id,
    location_id,
    sale_id,
    amount,
    transaction_type,
    note,
    user_name,
    payment_method,
    payment_reference,
    cash_drawer_id,
    cash_drawer_name
  )
  values (
    target_customer_id,
    target_location_id,
    null,
    -target_amount,
    'PAYMENT',
    coalesce(nullif(btrim(target_note), ''), 'Customer payment'),
    nullif(btrim(target_user_name), ''),
    normalized_method,
    nullif(btrim(target_payment_reference), ''),
    case when normalized_method = 'CASH' then target_cash_drawer_id else null end,
    case when normalized_method = 'CASH' then nullif(btrim(target_cash_drawer_name), '') else null end
  )
  returning transaction_id into payment_transaction_id_local;

  payment_id_local := 'PAY-' || lpad(payment_transaction_id_local::text, 6, '0');

  update public.customer_account_transactions
  set payment_id = payment_id_local
  where transaction_id = payment_transaction_id_local;

  for sale_row in
    select
      sale_id,
      greatest(coalesce(total_amount, 0) - coalesce(returned_amount, 0), 0)::numeric(12, 2) as sale_total,
      coalesce(amount_paid, 0)::numeric(12, 2) as amount_paid
    from public.sales
    where customer_id = target_customer_id
      and payment_method = 'ACCOUNT'
      and coalesce(payment_status, 'PAID') <> 'PAID'
    order by created_at asc, sale_id asc
    for update
  loop
    exit when remaining_payment <= 0;

    if sale_row.sale_total - sale_row.amount_paid <= 0 then
      update public.sales
      set amount_paid = sale_row.sale_total,
          payment_status = 'PAID'
      where sale_id = sale_row.sale_id;
      continue;
    end if;

    applied_amount := least(remaining_payment, sale_row.sale_total - sale_row.amount_paid);
    new_amount_paid := sale_row.amount_paid + applied_amount;

    update public.sales
    set amount_paid = new_amount_paid,
        payment_status = case
          when new_amount_paid >= sale_row.sale_total then 'PAID'
          else 'UNPAID'
        end
    where sale_id = sale_row.sale_id;

    insert into public.customer_account_payment_allocations (
      payment_transaction_id,
      customer_id,
      sale_id,
      amount
    )
    values (
      payment_transaction_id_local,
      target_customer_id,
      sale_row.sale_id,
      applied_amount
    );

    applied_parts := array_append(
      applied_parts,
      'sale #' || sale_row.sale_id || ' ' || to_char(applied_amount, 'FM9999999990.00')
    );

    remaining_payment := remaining_payment - applied_amount;
  end loop;

  if coalesce(array_length(applied_parts, 1), 0) = 0 then
    applied_note := 'Customer payment. No unpaid account sales were available to apply this payment to.';
  else
    applied_note := 'Customer payment applied to ' || array_to_string(applied_parts, '; ');
    if remaining_payment > 0 then
      applied_note := applied_note || '; unapplied ' || to_char(remaining_payment, 'FM9999999990.00');
    end if;
  end if;

  combined_note := case
    when target_note is not null and btrim(target_note) <> '' then target_note || ' | ' || applied_note
    else applied_note
  end;

  update public.customer_account_transactions
  set note = combined_note
  where transaction_id = payment_transaction_id_local;

  payment_transaction_id := payment_transaction_id_local;
  payment_id := payment_id_local;
  new_balance := (customer_row.current_balance - target_amount)::numeric(12, 2);

  return next;
end;
$$;

revoke all on function public.record_customer_account_payment(int, numeric, text, text, int, text, text, bigint, text) from public;
grant execute on function public.record_customer_account_payment(int, numeric, text, text, int, text, text, bigint, text) to authenticated;

create or replace function public.record_customer_account_payment(
  target_customer_id int,
  target_amount numeric(12, 2),
  target_note text,
  target_user_name text,
  target_location_id int
)
returns table (
  payment_transaction_id int,
  payment_id text,
  applied_note text,
  new_balance numeric(12, 2)
)
language sql
security definer
set search_path = public
as $$
  select *
  from public.record_customer_account_payment(
    target_customer_id,
    target_amount,
    target_note,
    target_user_name,
    target_location_id,
    null::text,
    null::text,
    null::bigint,
    null::text
  )
$$;

revoke all on function public.record_customer_account_payment(int, numeric, text, text, int) from public;
grant execute on function public.record_customer_account_payment(int, numeric, text, text, int) to authenticated;

notify pgrst, 'reload schema';

commit;
