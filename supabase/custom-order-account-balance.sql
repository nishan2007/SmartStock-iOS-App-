begin;

create or replace function public.charge_custom_order_balance_to_account(
  target_customer_id int,
  target_custom_order_id bigint,
  target_amount numeric(12, 2),
  target_note text default null,
  target_user_name text default null,
  target_location_id int default null,
  target_device_id text default null,
  target_device_name text default null
)
returns table (
  account_transaction_id int,
  new_balance numeric(12, 2)
)
language plpgsql
security definer
set search_path = public
as $$
declare
  customer_row record;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if target_amount is null or target_amount <= 0 then
    raise exception 'Account charge amount must be greater than zero.';
  end if;

  if target_location_id is not null and not public.current_app_user_can_access_location(target_location_id) then
    raise exception 'You do not have access to this store.';
  end if;

  if not (
    public.current_app_user_has_mobile_permission('create_custom_order')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
  ) then
    raise exception 'You do not have permission to charge custom orders to customer accounts.';
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

  if customer_row.current_balance + target_amount > customer_row.credit_limit then
    raise exception 'Custom order balance exceeds the customer credit limit.';
  end if;

  update public.customer_accounts
  set current_balance = customer_row.current_balance + target_amount
  where customer_id = target_customer_id;

  insert into public.customer_account_transactions (
    customer_id,
    location_id,
    sale_id,
    custom_order_id,
    amount,
    transaction_type,
    note,
    user_name,
    device_id,
    device_name
  )
  values (
    target_customer_id,
    target_location_id,
    null,
    target_custom_order_id,
    target_amount,
    'CUSTOM_ORDER_CREDIT',
    coalesce(nullif(btrim(target_note), ''), 'Custom order balance charged to account'),
    nullif(btrim(target_user_name), ''),
    nullif(btrim(target_device_id), ''),
    nullif(btrim(target_device_name), '')
  )
  returning transaction_id into account_transaction_id;

  new_balance := (customer_row.current_balance + target_amount)::numeric(12, 2);
  return next;
end;
$$;

revoke all on function public.charge_custom_order_balance_to_account(int, bigint, numeric, text, text, int, text, text) from public;
grant execute on function public.charge_custom_order_balance_to_account(int, bigint, numeric, text, text, int, text, text) to authenticated;

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
  item_row record;
  payment_transaction_id_local int;
  payment_id_local text;
  remaining_payment numeric(12, 2);
  applied_amount numeric(12, 2);
  next_amount_paid numeric(12, 2);
  item_balance numeric(12, 2);
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
    custom_order_id,
    amount,
    transaction_type,
    note,
    user_name
  )
  values (
    target_customer_id,
    target_location_id,
    null,
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

  for item_row in
    select
      'sale'::text as item_type,
      s.sale_id,
      null::bigint as custom_order_id,
      greatest(coalesce(s.total_amount, 0) - coalesce(s.returned_amount, 0), 0)::numeric(12, 2) as total_amount,
      coalesce(s.amount_paid, 0)::numeric(12, 2) as amount_paid,
      s.created_at
    from public.sales s
    where s.customer_id = target_customer_id
      and s.payment_method = 'ACCOUNT'
      and coalesce(s.payment_status, 'PAID') <> 'PAID'
      and greatest(coalesce(s.total_amount, 0) - coalesce(s.returned_amount, 0), 0) - coalesce(s.amount_paid, 0) > 0
    union all
    select
      'custom_order'::text as item_type,
      null::int as sale_id,
      co.custom_order_id,
      coalesce(co.total_amount, 0)::numeric(12, 2) as total_amount,
      coalesce(co.amount_paid, 0)::numeric(12, 2) as amount_paid,
      co.created_at
    from public.custom_orders co
    where co.customer_id = target_customer_id
      and coalesce(co.payment_status, 'PAID') <> 'PAID'
      and coalesce(co.balance_due, 0) > 0
      and exists (
        select 1
        from public.customer_account_transactions t
        where t.customer_id = target_customer_id
          and t.custom_order_id = co.custom_order_id
          and t.transaction_type = 'CUSTOM_ORDER_CREDIT'
      )
    order by created_at asc, sale_id asc nulls last, custom_order_id asc nulls last
  loop
    exit when remaining_payment <= 0;

    if item_row.item_type = 'sale' then
      item_balance := item_row.total_amount - item_row.amount_paid;
      applied_amount := least(remaining_payment, item_balance);
      next_amount_paid := item_row.amount_paid + applied_amount;

      update public.sales
      set amount_paid = next_amount_paid,
          payment_status = case
            when next_amount_paid >= item_row.total_amount then 'PAID'
            else 'UNPAID'
          end
      where sale_id = item_row.sale_id;

      insert into public.customer_account_payment_allocations (
        payment_transaction_id,
        customer_id,
        sale_id,
        custom_order_id,
        amount
      )
      values (
        payment_transaction_id_local,
        target_customer_id,
        item_row.sale_id,
        null,
        applied_amount
      );

      applied_parts := array_append(
        applied_parts,
        'sale #' || item_row.sale_id || ' ' || to_char(applied_amount, 'FM9999999990.00')
      );
    else
      item_balance := item_row.total_amount - item_row.amount_paid;
      applied_amount := least(remaining_payment, item_balance);
      next_amount_paid := item_row.amount_paid + applied_amount;

      update public.custom_orders
      set amount_paid = next_amount_paid,
          balance_due = greatest(item_row.total_amount - next_amount_paid, 0),
          payment_status = case
            when next_amount_paid >= item_row.total_amount then 'PAID'
            else 'PARTIAL'
          end
      where custom_order_id = item_row.custom_order_id;

      insert into public.customer_account_payment_allocations (
        payment_transaction_id,
        customer_id,
        sale_id,
        custom_order_id,
        amount
      )
      values (
        payment_transaction_id_local,
        target_customer_id,
        null,
        item_row.custom_order_id,
        applied_amount
      );

      applied_parts := array_append(
        applied_parts,
        'custom order #' || item_row.custom_order_id || ' ' || to_char(applied_amount, 'FM9999999990.00')
      );
    end if;

    remaining_payment := remaining_payment - applied_amount;
  end loop;

  if coalesce(array_length(applied_parts, 1), 0) = 0 then
    applied_note := 'Customer payment. No unpaid account items were available to apply this payment to.';
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

notify pgrst, 'reload schema';

commit;
