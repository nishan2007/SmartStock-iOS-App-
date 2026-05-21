-- Custom Orders RLS for the SmartStock iOS app.
--
-- This script assumes the custom order tables already exist. It does not create
-- duplicate workflow tables. It uses the iOS mobile_permissions model plus
-- user_locations to keep custom orders scoped to allowed store/location access.

begin;

alter table public.custom_order_items
  add column if not exists sku text;

alter table public.custom_order_item_variants
  add column if not exists sku text;

create or replace function public.custom_order_sku_slug(value text)
returns text
language sql
immutable
as $$
  select nullif(
    array_to_string(
      array(
        select case
          when word = 'ADHESIVE' then 'ADH'
          when word = 'BANNER' then 'BNR'
          when word = 'CANVAS' then 'CNV'
          when word = 'GLOSSY' then 'GLSY'
          when word = 'MATTE' then 'MAT'
          when word = 'MEDIUM' then 'MED'
          when word = 'PURPLE' then 'PRPL'
          when word = 'SHIRT' then 'SHRT'
          when word = 'SMALL' then 'SML'
          when word = 'VINYL' then 'VNL'
          when length(word) <= 4 then word
          else coalesce(
            nullif(left(left(word, 1) || regexp_replace(substr(word, 2), '[AEIOU]', '', 'g'), 4), ''),
            left(word, 4)
          )
        end
        from regexp_split_to_table(upper(coalesce(value, '')), '[^A-Z0-9]+') as word
        where word <> ''
      ),
      '-'
    ),
    ''
  )
$$;

create or replace function public.custom_order_generated_sku(parts text[])
returns text
language sql
immutable
as $$
  select 'CO-' || coalesce(
    nullif(
      array_to_string(
        array(
          select public.custom_order_sku_slug(part)
          from unnest(parts) as part
          where public.custom_order_sku_slug(part) is not null
        ),
        '-'
      ),
      ''
    ),
    'ITEM'
  )
$$;

create or replace function public.set_custom_order_item_sku()
returns trigger
language plpgsql
as $$
begin
  new.sku := public.custom_order_generated_sku(array[new.item_name]);
  return new;
end;
$$;

create or replace function public.set_custom_order_variant_sku()
returns trigger
language plpgsql
as $$
declare
  parent_name text;
begin
  select item_name
  into parent_name
  from public.custom_order_items
  where custom_item_id = new.custom_item_id;

  new.sku := public.custom_order_generated_sku(array[parent_name, new.variant_name]);
  return new;
end;
$$;

drop trigger if exists set_custom_order_item_sku on public.custom_order_items;
create trigger set_custom_order_item_sku
before insert or update of item_name
on public.custom_order_items
for each row
execute function public.set_custom_order_item_sku();

drop trigger if exists set_custom_order_variant_sku on public.custom_order_item_variants;
create trigger set_custom_order_variant_sku
before insert or update of custom_item_id, variant_name
on public.custom_order_item_variants
for each row
execute function public.set_custom_order_variant_sku();

update public.custom_order_items
set sku = public.custom_order_generated_sku(array[item_name])
where sku is null or btrim(sku) = '';

update public.custom_order_item_variants v
set sku = public.custom_order_generated_sku(array[i.item_name, v.variant_name])
from public.custom_order_items i
where i.custom_item_id = v.custom_item_id
  and (v.sku is null or btrim(v.sku) = '');

create unique index if not exists custom_order_items_sku_key
on public.custom_order_items (sku)
where sku is not null;

create unique index if not exists custom_order_item_variants_sku_key
on public.custom_order_item_variants (sku)
where sku is not null;

insert into public.mobile_permissions (permission_key, display_name, permission_group, sort_order)
values
  ('create_custom_order', 'Create Custom Order', 'Sales', 18),
  ('manage_custom_orders', 'Manage Custom Orders', 'Sales', 19),
  ('view_assigned_custom_orders', 'View Assigned Custom Orders', 'Sales', 20),
  ('orders_manager_dashboard', 'Orders Manager Dashboard', 'Sales', 21),
  ('orders_end_of_day', 'Orders End Of Day', 'Sales', 22),
  ('custom_order_refunds', 'Custom Order Refunds', 'Sales', 23),
  ('custom_order_line_returns', 'Custom Order Line Returns', 'Sales', 24),
  ('custom_order_line_delivery', 'Custom Order Line Delivery', 'Sales', 25),
  ('custom_order_line_discount', 'Custom Order Line Discount', 'Sales', 26),
  ('custom_order_deposit_override', 'Custom Order Deposit Override', 'Sales', 27),
  ('custom_order_refund_approval', 'Custom Order Refund Approval', 'Sales', 28),
  ('custom_order_production_steps', 'Custom Order Production Steps', 'Sales', 29),
  ('custom_order_cancel', 'Custom Order Cancel', 'Sales', 30),
  ('custom_order_overrides', 'Custom Order Overrides', 'Sales', 31),
  ('custom_order_items', 'Custom Order Items', 'Inventory', 146),
  ('custom_order_print_materials', 'Custom Order Print Materials', 'Inventory', 147),
  ('custom_order_deposit_settings', 'Custom Order Deposit Settings', 'Admin', 321),
  ('custom_order_refund_approval_settings', 'Custom Order Refund Approval Settings', 'Admin', 322)
on conflict (permission_key) do update
set display_name = excluded.display_name,
    permission_group = excluded.permission_group,
    sort_order = excluded.sort_order;

insert into public.role_mobile_permissions (role_id, permission_key)
select 1, permission_key
from public.mobile_permissions
where permission_key like 'custom_order%'
   or permission_key in ('create_custom_order', 'manage_custom_orders', 'view_assigned_custom_orders', 'orders_manager_dashboard', 'orders_end_of_day')
on conflict (role_id, permission_key) do nothing;

create or replace function public.current_app_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_user_id = auth.uid()
      and u.role_id = 1
  )
$$;

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

create or replace function public.current_app_user_has_mobile_permission(target_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.current_app_user_is_admin()
    or exists (
      select 1
      from public.users u
      join public.role_mobile_permissions rmp on rmp.role_id = u.role_id
      where u.auth_user_id = auth.uid()
        and rmp.permission_key = target_permission_key
    )
$$;

create or replace function public.current_app_user_can_access_location(target_location_id int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    target_location_id is null
    or public.current_app_user_is_admin()
    or exists (
      select 1
      from public.user_locations ul
      where ul.user_id = public.current_app_user_id()
        and ul.location_id = target_location_id
    )
$$;

revoke all on function public.current_app_user_is_admin() from public;
revoke all on function public.current_app_user_id() from public;
revoke all on function public.current_app_user_has_mobile_permission(text) from public;
revoke all on function public.current_app_user_can_access_location(int) from public;
grant execute on function public.current_app_user_is_admin() to authenticated;
grant execute on function public.current_app_user_id() to authenticated;
grant execute on function public.current_app_user_has_mobile_permission(text) to authenticated;
grant execute on function public.current_app_user_can_access_location(int) to authenticated;

alter table public.custom_orders enable row level security;
alter table public.custom_order_lines enable row level security;
alter table public.custom_order_payments enable row level security;
alter table public.custom_order_line_returns enable row level security;
alter table public.custom_order_line_deliveries enable row level security;
alter table public.custom_order_line_production_history enable row level security;
alter table public.custom_order_audit_log enable row level security;
alter table public.custom_order_status_history enable row level security;
alter table public.custom_order_items enable row level security;
alter table public.custom_order_item_variants enable row level security;
alter table public.custom_order_item_barcodes enable row level security;
alter table public.custom_order_item_movements enable row level security;
alter table public.custom_order_print_materials enable row level security;
alter table public.custom_order_print_size_presets enable row level security;
alter table public.custom_order_line_print_addons enable row level security;
alter table public.custom_order_design_placements enable row level security;
alter table public.company_customization enable row level security;
alter table public.customer_accounts enable row level security;
alter table public.customer_account_transactions enable row level security;
alter table public.customer_account_payment_allocations enable row level security;

drop policy if exists "iOS can read custom orders by location" on public.custom_orders;
drop policy if exists "iOS can create custom orders" on public.custom_orders;
drop policy if exists "iOS can update custom orders" on public.custom_orders;
drop policy if exists "iOS can read custom order lines by order" on public.custom_order_lines;
drop policy if exists "iOS can create custom order lines" on public.custom_order_lines;
drop policy if exists "iOS can update custom order lines" on public.custom_order_lines;
drop policy if exists "iOS can read custom order payments by order" on public.custom_order_payments;
drop policy if exists "iOS can create custom order payments" on public.custom_order_payments;
drop policy if exists "iOS can read custom order returns by order" on public.custom_order_line_returns;
drop policy if exists "iOS can create custom order returns" on public.custom_order_line_returns;
drop policy if exists "iOS can read custom order deliveries by order" on public.custom_order_line_deliveries;
drop policy if exists "iOS can create custom order deliveries" on public.custom_order_line_deliveries;
drop policy if exists "iOS can read custom order production history by order" on public.custom_order_line_production_history;
drop policy if exists "iOS can create custom order production history" on public.custom_order_line_production_history;
drop policy if exists "iOS can read custom order audit by order" on public.custom_order_audit_log;
drop policy if exists "iOS can create custom order audit" on public.custom_order_audit_log;
drop policy if exists "iOS can read custom order status history by order" on public.custom_order_status_history;
drop policy if exists "iOS can create custom order status history" on public.custom_order_status_history;
drop policy if exists "iOS can read custom order items" on public.custom_order_items;
drop policy if exists "iOS can manage custom order items" on public.custom_order_items;
drop policy if exists "iOS can read custom order item variants" on public.custom_order_item_variants;
drop policy if exists "iOS can manage custom order item variants" on public.custom_order_item_variants;
drop policy if exists "iOS can read custom order item barcodes" on public.custom_order_item_barcodes;
drop policy if exists "iOS can manage custom order item barcodes" on public.custom_order_item_barcodes;
drop policy if exists "iOS can read custom order item movements" on public.custom_order_item_movements;
drop policy if exists "iOS can create custom order item movements" on public.custom_order_item_movements;
drop policy if exists "iOS can read print materials" on public.custom_order_print_materials;
drop policy if exists "iOS can manage print materials" on public.custom_order_print_materials;
drop policy if exists "iOS can read print size presets" on public.custom_order_print_size_presets;
drop policy if exists "iOS can manage print size presets" on public.custom_order_print_size_presets;
drop policy if exists "iOS can read line print addons by order" on public.custom_order_line_print_addons;
drop policy if exists "iOS can create line print addons" on public.custom_order_line_print_addons;
drop policy if exists "iOS can update line print addons" on public.custom_order_line_print_addons;
drop policy if exists "iOS can delete line print addons" on public.custom_order_line_print_addons;
drop policy if exists "iOS can read design placements" on public.custom_order_design_placements;
drop policy if exists "iOS can manage design placements" on public.custom_order_design_placements;
drop policy if exists "iOS can read custom order company preferences" on public.company_customization;
drop policy if exists "iOS can manage custom order company preferences" on public.company_customization;
drop policy if exists "iOS can create customers for custom orders" on public.customer_accounts;
drop policy if exists "iOS can create custom order account transactions" on public.customer_account_transactions;
drop policy if exists "iOS can read custom order account transactions" on public.customer_account_transactions;
drop policy if exists "iOS can read custom order account allocations" on public.customer_account_payment_allocations;
drop policy if exists "iOS can create custom order account allocations" on public.customer_account_payment_allocations;

create policy "iOS can read custom orders by location"
on public.custom_orders
for select
to authenticated
using (
  public.current_app_user_can_access_location(location_id)
  and (
    public.current_app_user_has_mobile_permission('manage_custom_orders')
    or public.current_app_user_has_mobile_permission('orders_manager_dashboard')
    or public.current_app_user_has_mobile_permission('orders_end_of_day')
    or (
      public.current_app_user_has_mobile_permission('create_custom_order')
      and taken_by_user_id = public.current_app_user_id()
    )
    or (
      public.current_app_user_has_mobile_permission('view_assigned_custom_orders')
      and assigned_to_user_id = public.current_app_user_id()
    )
  )
);

create policy "iOS can create custom orders"
on public.custom_orders
for insert
to authenticated
with check (
  public.current_app_user_has_mobile_permission('create_custom_order')
  and public.current_app_user_can_access_location(location_id)
  and taken_by_user_id = public.current_app_user_id()
);

create policy "iOS can update custom orders"
on public.custom_orders
for update
to authenticated
using (
  public.current_app_user_can_access_location(location_id)
  and (
    public.current_app_user_has_mobile_permission('manage_custom_orders')
    or public.current_app_user_has_mobile_permission('custom_order_cancel')
    or public.current_app_user_has_mobile_permission('custom_order_deposit_override')
  )
)
with check (public.current_app_user_can_access_location(location_id));

create policy "iOS can read custom order lines by order"
on public.custom_order_lines
for select
to authenticated
using (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_lines.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can create custom order lines"
on public.custom_order_lines
for insert
to authenticated
with check (
  public.current_app_user_has_mobile_permission('create_custom_order')
  and exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_lines.custom_order_id
      and co.taken_by_user_id = public.current_app_user_id()
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can update custom order lines"
on public.custom_order_lines
for update
to authenticated
using (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_lines.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
  and (
    public.current_app_user_has_mobile_permission('manage_custom_orders')
    or public.current_app_user_has_mobile_permission('custom_order_line_delivery')
    or public.current_app_user_has_mobile_permission('custom_order_line_discount')
    or public.current_app_user_has_mobile_permission('custom_order_production_steps')
    or public.current_app_user_has_mobile_permission('custom_order_overrides')
  )
)
with check (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_lines.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can read custom order payments by order"
on public.custom_order_payments
for select
to authenticated
using (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_payments.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can create custom order payments"
on public.custom_order_payments
for insert
to authenticated
with check (
  (
    public.current_app_user_has_mobile_permission('create_custom_order')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
    or public.current_app_user_has_mobile_permission('custom_order_refunds')
  )
  and exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_payments.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can read custom order returns by order"
on public.custom_order_line_returns
for select
to authenticated
using (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_line_returns.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can create custom order returns"
on public.custom_order_line_returns
for insert
to authenticated
with check (
  (
    public.current_app_user_has_mobile_permission('custom_order_refunds')
    or public.current_app_user_has_mobile_permission('custom_order_line_returns')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
  )
  and exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_line_returns.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can read custom order deliveries by order"
on public.custom_order_line_deliveries
for select
to authenticated
using (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_line_deliveries.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can create custom order deliveries"
on public.custom_order_line_deliveries
for insert
to authenticated
with check (
  public.current_app_user_has_mobile_permission('custom_order_line_delivery')
  and exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_line_deliveries.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can read custom order production history by order"
on public.custom_order_line_production_history
for select
to authenticated
using (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_line_production_history.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can create custom order production history"
on public.custom_order_line_production_history
for insert
to authenticated
with check (
  public.current_app_user_has_mobile_permission('custom_order_production_steps')
  and exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_line_production_history.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can read custom order audit by order"
on public.custom_order_audit_log
for select
to authenticated
using (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_audit_log.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can create custom order audit"
on public.custom_order_audit_log
for insert
to authenticated
with check (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_audit_log.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can read custom order status history by order"
on public.custom_order_status_history
for select
to authenticated
using (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_status_history.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can create custom order status history"
on public.custom_order_status_history
for insert
to authenticated
with check (
  exists (
    select 1 from public.custom_orders co
    where co.custom_order_id = custom_order_status_history.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can read custom order items"
on public.custom_order_items
for select
to authenticated
using (
  public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('receiving')
  or (
    public.current_app_user_has_mobile_permission('create_custom_order')
    and is_active = true
  )
);

create policy "iOS can manage custom order items"
on public.custom_order_items
for all
to authenticated
using (public.current_app_user_has_mobile_permission('custom_order_items'))
with check (public.current_app_user_has_mobile_permission('custom_order_items'));

create policy "iOS can read custom order item variants"
on public.custom_order_item_variants
for select
to authenticated
using (
  public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('receiving')
  or (
    public.current_app_user_has_mobile_permission('create_custom_order')
    and is_active = true
  )
);

create policy "iOS can manage custom order item variants"
on public.custom_order_item_variants
for all
to authenticated
using (public.current_app_user_has_mobile_permission('custom_order_items'))
with check (public.current_app_user_has_mobile_permission('custom_order_items'));

create policy "iOS can read custom order item barcodes"
on public.custom_order_item_barcodes
for select
to authenticated
using (
  public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('receiving')
  or public.current_app_user_has_mobile_permission('create_custom_order')
);

create policy "iOS can manage custom order item barcodes"
on public.custom_order_item_barcodes
for all
to authenticated
using (public.current_app_user_has_mobile_permission('custom_order_items'))
with check (public.current_app_user_has_mobile_permission('custom_order_items'));

create policy "iOS can read custom order item movements"
on public.custom_order_item_movements
for select
to authenticated
using (
  public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('receiving')
  or public.current_app_user_has_mobile_permission('view_receiving_history')
);

create policy "iOS can create custom order item movements"
on public.custom_order_item_movements
for insert
to authenticated
with check (
  public.current_app_user_has_mobile_permission('receiving')
  or public.current_app_user_has_mobile_permission('custom_order_items')
);

create policy "iOS can read print materials"
on public.custom_order_print_materials
for select
to authenticated
using (
  public.current_app_user_has_mobile_permission('create_custom_order')
  or public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('custom_order_print_materials')
  or public.current_app_user_has_mobile_permission('manage_custom_orders')
);

create policy "iOS can manage print materials"
on public.custom_order_print_materials
for all
to authenticated
using (
  public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('custom_order_print_materials')
)
with check (
  public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('custom_order_print_materials')
);

create policy "iOS can read print size presets"
on public.custom_order_print_size_presets
for select
to authenticated
using (
  public.current_app_user_has_mobile_permission('create_custom_order')
  or public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('custom_order_print_materials')
  or public.current_app_user_has_mobile_permission('manage_custom_orders')
);

create policy "iOS can manage print size presets"
on public.custom_order_print_size_presets
for all
to authenticated
using (
  public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('custom_order_print_materials')
)
with check (
  public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('custom_order_print_materials')
);

create policy "iOS can read line print addons by order"
on public.custom_order_line_print_addons
for select
to authenticated
using (
  exists (
    select 1
    from public.custom_order_lines col
    join public.custom_orders co on co.custom_order_id = col.custom_order_id
    where col.custom_order_line_id = custom_order_line_print_addons.custom_order_line_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can create line print addons"
on public.custom_order_line_print_addons
for insert
to authenticated
with check (
  (
    public.current_app_user_has_mobile_permission('create_custom_order')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
  )
  and exists (
    select 1
    from public.custom_order_lines col
    join public.custom_orders co on co.custom_order_id = col.custom_order_id
    where col.custom_order_line_id = custom_order_line_print_addons.custom_order_line_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can update line print addons"
on public.custom_order_line_print_addons
for update
to authenticated
using (
  (
    public.current_app_user_has_mobile_permission('create_custom_order')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
  )
  and exists (
    select 1
    from public.custom_order_lines col
    join public.custom_orders co on co.custom_order_id = col.custom_order_id
    where col.custom_order_line_id = custom_order_line_print_addons.custom_order_line_id
      and public.current_app_user_can_access_location(co.location_id)
  )
)
with check (
  exists (
    select 1
    from public.custom_order_lines col
    join public.custom_orders co on co.custom_order_id = col.custom_order_id
    where col.custom_order_line_id = custom_order_line_print_addons.custom_order_line_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can delete line print addons"
on public.custom_order_line_print_addons
for delete
to authenticated
using (
  (
    public.current_app_user_has_mobile_permission('create_custom_order')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
  )
  and exists (
    select 1
    from public.custom_order_lines col
    join public.custom_orders co on co.custom_order_id = col.custom_order_id
    where col.custom_order_line_id = custom_order_line_print_addons.custom_order_line_id
      and public.current_app_user_can_access_location(co.location_id)
  )
);

create policy "iOS can read design placements"
on public.custom_order_design_placements
for select
to authenticated
using (
  public.current_app_user_has_mobile_permission('create_custom_order')
  or public.current_app_user_has_mobile_permission('custom_order_items')
  or public.current_app_user_has_mobile_permission('manage_custom_orders')
);

create policy "iOS can manage design placements"
on public.custom_order_design_placements
for all
to authenticated
using (public.current_app_user_has_mobile_permission('custom_order_items'))
with check (public.current_app_user_has_mobile_permission('custom_order_items'));

create policy "iOS can read custom order company preferences"
on public.company_customization
for select
to authenticated
using (
  public.current_app_user_can_access_location(location_id)
  and (
    public.current_app_user_has_mobile_permission('create_custom_order')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
    or public.current_app_user_has_mobile_permission('custom_order_deposit_settings')
    or public.current_app_user_has_mobile_permission('custom_order_refund_approval_settings')
    or public.current_app_user_has_mobile_permission('company_preferences')
  )
);

create policy "iOS can manage custom order company preferences"
on public.company_customization
for all
to authenticated
using (
  public.current_app_user_can_access_location(location_id)
  and (
    public.current_app_user_has_mobile_permission('company_preferences')
    or public.current_app_user_has_mobile_permission('custom_order_deposit_settings')
    or public.current_app_user_has_mobile_permission('custom_order_refund_approval_settings')
  )
)
with check (
  public.current_app_user_can_access_location(location_id)
  and (
    public.current_app_user_has_mobile_permission('company_preferences')
    or public.current_app_user_has_mobile_permission('custom_order_deposit_settings')
    or public.current_app_user_has_mobile_permission('custom_order_refund_approval_settings')
  )
);

create policy "iOS can create customers for custom orders"
on public.customer_accounts
for insert
to authenticated
with check (
  public.current_app_user_has_mobile_permission('create_custom_order')
  and customer_type_id = 1
  and is_business = false
);

create policy "iOS can create custom order account transactions"
on public.customer_account_transactions
for insert
to authenticated
with check (
  (
    public.current_app_user_has_mobile_permission('create_custom_order')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
  )
  and public.current_app_user_can_access_location(location_id)
);

create policy "iOS can read custom order account transactions"
on public.customer_account_transactions
for select
to authenticated
using (
  custom_order_id is not null
  and public.current_app_user_can_access_location(location_id)
  and (
    public.current_app_user_has_mobile_permission('manage_custom_orders')
    or public.current_app_user_has_mobile_permission('orders_end_of_day')
    or public.current_app_user_has_mobile_permission('customers')
    or public.current_app_user_has_mobile_permission('manage_customers')
  )
);

create policy "iOS can read custom order account allocations"
on public.customer_account_payment_allocations
for select
to authenticated
using (
  custom_order_id is not null
  and exists (
    select 1
    from public.custom_orders co
    where co.custom_order_id = customer_account_payment_allocations.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
  and (
    public.current_app_user_has_mobile_permission('manage_custom_orders')
    or public.current_app_user_has_mobile_permission('orders_end_of_day')
    or public.current_app_user_has_mobile_permission('customers')
    or public.current_app_user_has_mobile_permission('manage_customers')
  )
);

create policy "iOS can create custom order account allocations"
on public.customer_account_payment_allocations
for insert
to authenticated
with check (
  custom_order_id is not null
  and exists (
    select 1
    from public.custom_orders co
    where co.custom_order_id = customer_account_payment_allocations.custom_order_id
      and public.current_app_user_can_access_location(co.location_id)
  )
  and (
    public.current_app_user_has_mobile_permission('create_custom_order')
    or public.current_app_user_has_mobile_permission('manage_custom_orders')
    or public.current_app_user_has_mobile_permission('customers')
    or public.current_app_user_has_mobile_permission('manage_customers')
  )
);

notify pgrst, 'reload schema';

commit;
