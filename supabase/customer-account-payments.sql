begin;

create or replace function public.current_app_user_can_view_customer_accounts()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('customers')
    or public.current_app_user_has_mobile_permission('manage_customers')
$$;

create or replace function public.current_app_user_can_record_customer_payments()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('manage_customers')
$$;

create or replace function public.current_app_user_can_view_sales_at_location(target_location_id int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.current_app_user_has_location(target_location_id)
    and (
      coalesce(public.current_app_user_is_admin(), false)
      or public.current_app_user_has_mobile_permission('make_sale')
      or public.current_app_user_has_mobile_permission('view_sales')
      or public.current_app_user_has_mobile_permission('customers')
      or public.current_app_user_has_mobile_permission('manage_customers')
    )
$$;

revoke all on function public.current_app_user_can_view_customer_accounts() from public;
revoke all on function public.current_app_user_can_record_customer_payments() from public;
revoke all on function public.current_app_user_can_view_sales_at_location(int) from public;

grant execute on function public.current_app_user_can_view_customer_accounts() to authenticated;
grant execute on function public.current_app_user_can_record_customer_payments() to authenticated;
grant execute on function public.current_app_user_can_view_sales_at_location(int) to authenticated;

alter table public.customer_account_transactions
add column if not exists location_id integer null references public.locations(location_id);

create index if not exists idx_customer_account_transactions_location_created
on public.customer_account_transactions using btree (location_id, created_at desc);

alter table public.customer_account_transactions enable row level security;
alter table public.customer_account_payment_allocations enable row level security;

drop policy if exists "Users can read customer account transactions" on public.customer_account_transactions;
drop policy if exists "Users can insert customer account transactions" on public.customer_account_transactions;
drop policy if exists "Users can read customer account payment allocations" on public.customer_account_payment_allocations;

create policy "Users can read customer account transactions"
on public.customer_account_transactions
for select
to authenticated
using (
  public.current_app_user_can_view_customer_accounts()
);

create policy "Users can insert customer account transactions"
on public.customer_account_transactions
for insert
to authenticated
with check (
  public.current_app_user_can_view_customer_accounts()
  and (
    (
      public.current_app_user_has_mobile_permission('make_sale')
      and transaction_type in ('SALE_CREDIT', 'SALE_PAID')
    )
    or (
      public.current_app_user_can_record_customer_payments()
      and transaction_type in ('PAYMENT', 'MANUAL_CHARGE')
    )
  )
);

create policy "Users can read customer account payment allocations"
on public.customer_account_payment_allocations
for select
to authenticated
using (
  public.current_app_user_can_view_customer_accounts()
);

create or replace function public.record_customer_account_payment(
  target_customer_id int,
  target_amount numeric(12, 2),
  target_note text default null,
  target_user_name text default null,
  target_location_id int default null
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
    user_name
  )
  values (
    target_customer_id,
    target_location_id,
    null,
    -target_amount,
    'PAYMENT',
    coalesce(nullif(btrim(target_note), ''), 'Customer payment'),
    nullif(btrim(target_user_name), '')
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

revoke all on function public.record_customer_account_payment(int, numeric, text, text, int) from public;
grant execute on function public.record_customer_account_payment(int, numeric, text, text, int) to authenticated;

create or replace function public.record_customer_account_payment(
  target_customer_id int,
  target_amount numeric(12, 2),
  target_note text,
  target_user_name text
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
    null::int
  )
$$;

revoke all on function public.record_customer_account_payment(int, numeric, text, text) from public;
grant execute on function public.record_customer_account_payment(int, numeric, text, text) to authenticated;

create or replace function public.record_customer_account_payment(
  target_customer_id int,
  target_amount numeric(12, 2),
  target_user_name text
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
    null::text,
    target_user_name,
    null::int
  )
$$;

revoke all on function public.record_customer_account_payment(int, numeric, text) from public;
grant execute on function public.record_customer_account_payment(int, numeric, text) to authenticated;

notify pgrst, 'reload schema';

commit;
