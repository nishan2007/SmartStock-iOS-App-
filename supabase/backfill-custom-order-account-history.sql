-- Backfill historical custom order account ledger data.
-- Applied to Supabase as migration: backfill_custom_order_account_history.

create temp table tmp_custom_order_account_backfill on commit drop as
select
  co.custom_order_id,
  co.order_number,
  co.customer_id,
  co.location_id,
  co.balance_due::numeric(12, 2) as balance_due
from public.custom_orders co
where coalesce(co.balance_due, 0) > 0
  and coalesce(co.payment_status, 'PAID') <> 'PAID'
  and not exists (
    select 1
    from public.customer_account_transactions t
    where t.custom_order_id = co.custom_order_id
      and t.transaction_type = 'CUSTOM_ORDER_CREDIT'
  );

with candidates as (
  select
    t.transaction_id,
    p.custom_order_payment_id,
    p.payment_amount,
    p.payment_action,
    row_number() over (
      partition by t.transaction_id
      order by abs(extract(epoch from (p.created_at - t.created_at))) asc, p.custom_order_payment_id asc
    ) as transaction_rank,
    row_number() over (
      partition by p.custom_order_payment_id
      order by abs(extract(epoch from (p.created_at - t.created_at))) asc, t.transaction_id asc
    ) as payment_rank
  from public.customer_account_transactions t
  join public.custom_order_payments p
    on p.custom_order_id = t.custom_order_id
   and (
     (t.transaction_type = 'CUSTOM_ORDER_PAID' and coalesce(p.payment_action, 'PAYMENT') = 'PAYMENT')
     or (t.transaction_type = 'CUSTOM_ORDER_REFUND' and coalesce(p.payment_action, 'PAYMENT') = 'REFUND')
   )
  where t.custom_order_id is not null
    and t.transaction_type in ('CUSTOM_ORDER_PAID', 'CUSTOM_ORDER_REFUND')
    and nullif(btrim(coalesce(t.payment_id, '')), '') is null
), matched as (
  select *
  from candidates
  where transaction_rank = 1
    and payment_rank = 1
)
update public.customer_account_transactions t
set
  payment_id = 'COP-' || lpad(m.custom_order_payment_id::text, 6, '0'),
  amount = case
    when t.transaction_type = 'CUSTOM_ORDER_PAID'
      and coalesce(t.amount, 0) = 0
      and coalesce(m.payment_action, 'PAYMENT') = 'PAYMENT'
    then m.payment_amount
    else t.amount
  end,
  note = case
    when t.note is null or position('payment_id=' in t.note) = 0
    then coalesce(t.note || '; ', '') || 'payment_id=COP-' || lpad(m.custom_order_payment_id::text, 6, '0')
    else t.note
  end
from matched m
where t.transaction_id = m.transaction_id;

insert into public.customer_account_transactions (
  customer_id,
  location_id,
  sale_id,
  custom_order_id,
  amount,
  transaction_type,
  note,
  payment_id,
  user_name,
  device_id,
  device_name,
  created_at
)
select
  co.customer_id,
  co.location_id,
  null,
  p.custom_order_id,
  case
    when coalesce(p.payment_action, 'PAYMENT') = 'REFUND' then -p.payment_amount
    else p.payment_amount
  end,
  case
    when coalesce(p.payment_action, 'PAYMENT') = 'REFUND' then 'CUSTOM_ORDER_REFUND'
    else 'CUSTOM_ORDER_PAID'
  end,
  'Backfilled custom order payment. order_number=' || co.order_number || ', payment_method=' || p.payment_method || ', payment_id=COP-' || lpad(p.custom_order_payment_id::text, 6, '0'),
  'COP-' || lpad(p.custom_order_payment_id::text, 6, '0'),
  p.taken_by_name,
  p.device_id,
  p.device_name,
  p.created_at
from public.custom_order_payments p
join public.custom_orders co
  on co.custom_order_id = p.custom_order_id
where coalesce(p.payment_method, '') <> 'ACCOUNT'
  and not exists (
    select 1
    from public.customer_account_transactions t
    where t.custom_order_id = p.custom_order_id
      and t.payment_id = 'COP-' || lpad(p.custom_order_payment_id::text, 6, '0')
  );

update public.customer_accounts ca
set current_balance = coalesce(ca.current_balance, 0) + charges.total_charge
from (
  select customer_id, sum(balance_due)::numeric(12, 2) as total_charge
  from tmp_custom_order_account_backfill
  group by customer_id
) charges
where ca.customer_id = charges.customer_id;

insert into public.customer_account_transactions (
  customer_id,
  location_id,
  sale_id,
  custom_order_id,
  amount,
  transaction_type,
  note,
  payment_id,
  user_name,
  created_at
)
select
  customer_id,
  location_id,
  null,
  custom_order_id,
  balance_due,
  'CUSTOM_ORDER_CREDIT',
  'Backfilled custom order balance. order_number=' || order_number,
  null,
  'System',
  now()
from tmp_custom_order_account_backfill;

update public.customer_account_transactions
set
  payment_id = 'ADJ-' || lpad(transaction_id::text, 6, '0'),
  note = coalesce(note || '; ', '') || 'adjustment_id=ADJ-' || lpad(transaction_id::text, 6, '0')
where custom_order_id is not null
  and transaction_type in ('CUSTOM_ORDER_PAID', 'CUSTOM_ORDER_REFUND')
  and nullif(btrim(coalesce(payment_id, '')), '') is null;
