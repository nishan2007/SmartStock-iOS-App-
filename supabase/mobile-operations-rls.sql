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

create or replace function public.current_app_user_has_location(target_location_id int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or target_location_id in (
      select location_id
      from public.current_app_user_location_ids()
    )
$$;

create or replace function public.current_app_user_can_view_inventory()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('inventory')
    or public.current_app_user_has_mobile_permission('edit_item')
    or public.current_app_user_has_mobile_permission('new_item')
    or public.current_app_user_has_mobile_permission('make_sale')
    or public.current_app_user_has_mobile_permission('receiving')
    or public.current_app_user_has_mobile_permission('store_transfer')
    or public.current_app_user_has_mobile_permission('view_receiving_history')
$$;

create or replace function public.current_app_user_can_manage_product_catalog()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('new_item')
    or public.current_app_user_has_mobile_permission('edit_item')
$$;

create or replace function public.current_app_user_can_create_products()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('new_item')
$$;

create or replace function public.current_app_user_can_edit_products()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_app_user_is_admin(), false)
    or public.current_app_user_has_mobile_permission('edit_item')
$$;

create or replace function public.current_app_user_can_manage_inventory_for_location(target_location_id int)
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
      or public.current_app_user_has_mobile_permission('new_item')
      or public.current_app_user_has_mobile_permission('edit_item')
      or public.current_app_user_has_mobile_permission('adjust_inventory_quantity')
      or public.current_app_user_has_mobile_permission('receiving')
      or public.current_app_user_has_mobile_permission('store_transfer')
      or public.current_app_user_has_mobile_permission('make_sale')
    )
$$;

create or replace function public.current_app_user_can_sell_at_location(target_location_id int)
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
    )
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
    )
$$;

create or replace function public.current_app_user_can_receive_at_location(target_location_id int)
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
      or public.current_app_user_has_mobile_permission('receiving')
      or public.current_app_user_has_mobile_permission('store_transfer')
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
    public.current_app_user_has_location(target_location_id)
    and (
      coalesce(public.current_app_user_is_admin(), false)
      or public.current_app_user_has_mobile_permission('receiving')
      or public.current_app_user_has_mobile_permission('view_receiving_history')
    )
$$;

create or replace function public.current_app_user_can_create_store_transfer(
  from_target_location_id int,
  to_target_location_id int
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      coalesce(public.current_app_user_is_admin(), false)
      or public.current_app_user_has_mobile_permission('store_transfer')
    )
    and public.current_app_user_has_location(from_target_location_id)
    and public.current_app_user_has_location(to_target_location_id)
$$;

create or replace function public.current_app_user_can_view_store_transfer(
  from_target_location_id int,
  to_target_location_id int
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      coalesce(public.current_app_user_is_admin(), false)
      or public.current_app_user_has_mobile_permission('store_transfer')
    )
    and (
      public.current_app_user_has_location(from_target_location_id)
      or public.current_app_user_has_location(to_target_location_id)
    )
$$;

create or replace function public.current_app_user_can_receive_store_transfer(
  to_target_location_id int
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      coalesce(public.current_app_user_is_admin(), false)
      or public.current_app_user_has_mobile_permission('store_transfer')
    )
    and public.current_app_user_has_location(to_target_location_id)
$$;

create or replace function public.current_app_user_can_verify_store_transfer_quantity(
  to_target_location_id int
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      coalesce(public.current_app_user_is_admin(), false)
      or public.current_app_user_has_mobile_permission('verify_store_transfer_quantity')
    )
    and public.current_app_user_has_location(to_target_location_id)
$$;

revoke all on function public.current_app_user_id() from public;
revoke all on function public.current_app_user_role_id() from public;
revoke all on function public.current_app_user_is_admin() from public;
revoke all on function public.current_app_user_has_mobile_permission(text) from public;
revoke all on function public.current_app_user_location_ids() from public;
revoke all on function public.current_app_user_has_location(int) from public;
revoke all on function public.current_app_user_can_view_inventory() from public;
revoke all on function public.current_app_user_can_manage_product_catalog() from public;
revoke all on function public.current_app_user_can_create_products() from public;
revoke all on function public.current_app_user_can_edit_products() from public;
revoke all on function public.current_app_user_can_manage_inventory_for_location(int) from public;
revoke all on function public.current_app_user_can_sell_at_location(int) from public;
revoke all on function public.current_app_user_can_view_sales_at_location(int) from public;
revoke all on function public.current_app_user_can_receive_at_location(int) from public;
revoke all on function public.current_app_user_can_view_receiving_at_location(int) from public;
revoke all on function public.current_app_user_can_create_store_transfer(int, int) from public;
revoke all on function public.current_app_user_can_view_store_transfer(int, int) from public;
revoke all on function public.current_app_user_can_receive_store_transfer(int) from public;
revoke all on function public.current_app_user_can_verify_store_transfer_quantity(int) from public;

grant execute on function public.current_app_user_id() to authenticated;
grant execute on function public.current_app_user_role_id() to authenticated;
grant execute on function public.current_app_user_is_admin() to authenticated;
grant execute on function public.current_app_user_has_mobile_permission(text) to authenticated;
grant execute on function public.current_app_user_location_ids() to authenticated;
grant execute on function public.current_app_user_has_location(int) to authenticated;
grant execute on function public.current_app_user_can_view_inventory() to authenticated;
grant execute on function public.current_app_user_can_manage_product_catalog() to authenticated;
grant execute on function public.current_app_user_can_create_products() to authenticated;
grant execute on function public.current_app_user_can_edit_products() to authenticated;
grant execute on function public.current_app_user_can_manage_inventory_for_location(int) to authenticated;
grant execute on function public.current_app_user_can_sell_at_location(int) to authenticated;
grant execute on function public.current_app_user_can_view_sales_at_location(int) to authenticated;
grant execute on function public.current_app_user_can_receive_at_location(int) to authenticated;
grant execute on function public.current_app_user_can_view_receiving_at_location(int) to authenticated;
grant execute on function public.current_app_user_can_create_store_transfer(int, int) to authenticated;
grant execute on function public.current_app_user_can_view_store_transfer(int, int) to authenticated;
grant execute on function public.current_app_user_can_receive_store_transfer(int) to authenticated;
grant execute on function public.current_app_user_can_verify_store_transfer_quantity(int) to authenticated;

alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.categories enable row level security;
alter table public.vendors enable row level security;
alter table public.product_barcodes enable row level security;
alter table public.receiving_batches enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.store_transfers enable row level security;
alter table public.store_transfer_items enable row level security;

drop policy if exists "Users can read products for inventory features" on public.products;
drop policy if exists "Users can create products" on public.products;
drop policy if exists "Users can update products" on public.products;

drop policy if exists "Users can read inventory at allowed stores" on public.inventory;
drop policy if exists "Users can create inventory at allowed stores" on public.inventory;
drop policy if exists "Users can update inventory at allowed stores" on public.inventory;
drop policy if exists "Users can read inventory for selling at allowed stores" on public.inventory;
drop policy if exists "Users can update inventory for selling at allowed stores" on public.inventory;

drop policy if exists "Users can read inventory movements at allowed stores" on public.inventory_movements;
drop policy if exists "Users can insert inventory movements at allowed stores" on public.inventory_movements;
drop policy if exists "Users can read receiving movements for allowed stores" on public.inventory_movements;
drop policy if exists "Users can insert receive movements for allowed stores" on public.inventory_movements;
drop policy if exists "Users can read sale movements at allowed stores" on public.inventory_movements;
drop policy if exists "Users can insert sale movements at allowed stores" on public.inventory_movements;

drop policy if exists "Users can read categories for inventory features" on public.categories;
drop policy if exists "Users can manage categories" on public.categories;
drop policy if exists "Users can read vendors for inventory features" on public.vendors;
drop policy if exists "Users can manage vendors" on public.vendors;

drop policy if exists "Users can read product barcodes for inventory features" on public.product_barcodes;
drop policy if exists "Users can insert product barcodes for editable products" on public.product_barcodes;
drop policy if exists "Users can delete product barcodes for editable products" on public.product_barcodes;
drop policy if exists "Users can read product barcodes at assigned stores" on public.product_barcodes;

drop policy if exists "Users can read receiving batches for allowed stores" on public.receiving_batches;
drop policy if exists "Users can insert receiving batches for allowed stores" on public.receiving_batches;

drop policy if exists "Users can read sales at allowed stores" on public.sales;
drop policy if exists "Users can insert sales at allowed stores" on public.sales;
drop policy if exists "Users can read sale items for allowed sales" on public.sale_items;
drop policy if exists "Users can insert sale items for allowed sales" on public.sale_items;

drop policy if exists "Users can read store transfers they can access" on public.store_transfers;
drop policy if exists "Users can create store transfers between assigned stores" on public.store_transfers;
drop policy if exists "Users can receive destination store transfers" on public.store_transfers;
drop policy if exists "Users can read transfer items for visible transfers" on public.store_transfer_items;
drop policy if exists "Users can insert transfer items for owned transfers" on public.store_transfer_items;
drop policy if exists "Users can verify transfer item quantities during receive" on public.store_transfer_items;

create policy "Users can read products for inventory features"
on public.products
for select
to authenticated
using (public.current_app_user_can_view_inventory());

create policy "Users can create products"
on public.products
for insert
to authenticated
with check (
  public.current_app_user_can_create_products()
  and coalesce(created_by_user_id, public.current_app_user_id()) = public.current_app_user_id()
);

create policy "Users can update products"
on public.products
for update
to authenticated
using (public.current_app_user_can_edit_products())
with check (public.current_app_user_can_edit_products());

create policy "Users can read inventory at allowed stores"
on public.inventory
for select
to authenticated
using (
  public.current_app_user_can_view_inventory()
  and public.current_app_user_has_location(location_id)
);

create policy "Users can create inventory at allowed stores"
on public.inventory
for insert
to authenticated
with check (public.current_app_user_can_manage_inventory_for_location(location_id));

create policy "Users can update inventory at allowed stores"
on public.inventory
for update
to authenticated
using (public.current_app_user_can_manage_inventory_for_location(location_id))
with check (public.current_app_user_can_manage_inventory_for_location(location_id));

create policy "Users can read inventory movements at allowed stores"
on public.inventory_movements
for select
to authenticated
using (
  public.current_app_user_has_location(location_id)
  and (
    (reason in ('receive', 'INVENTORY_ENTRY') and public.current_app_user_can_view_receiving_at_location(location_id))
    or (reason in ('sale', 'SALE') and public.current_app_user_can_view_sales_at_location(location_id))
    or (reason in ('TRANSFER_OUT', 'INVENTORY_ENTRY', 'TRANSFER_ADJUSTMENT') and public.current_app_user_can_view_inventory())
    or (reason in ('NEW_ITEM', 'MANUAL_ADJUSTMENT') and public.current_app_user_can_view_inventory())
    or (reason not in ('receive', 'sale', 'SALE', 'NEW_ITEM', 'MANUAL_ADJUSTMENT') and public.current_app_user_can_view_inventory())
  )
);

create policy "Users can insert inventory movements at allowed stores"
on public.inventory_movements
for insert
to authenticated
with check (
  public.current_app_user_has_location(location_id)
  and (
    (reason in ('receive', 'INVENTORY_ENTRY') and public.current_app_user_can_receive_at_location(location_id))
    or (reason in ('sale', 'SALE') and public.current_app_user_can_sell_at_location(location_id))
    or (reason in ('TRANSFER_OUT', 'INVENTORY_ENTRY', 'TRANSFER_ADJUSTMENT') and public.current_app_user_can_manage_inventory_for_location(location_id))
    or (reason in ('NEW_ITEM', 'MANUAL_ADJUSTMENT') and public.current_app_user_can_manage_inventory_for_location(location_id))
  )
);

create policy "Users can read categories for inventory features"
on public.categories
for select
to authenticated
using (public.current_app_user_can_view_inventory());

create policy "Users can manage categories"
on public.categories
for all
to authenticated
using (
  public.current_app_user_is_admin()
  or public.current_app_user_has_mobile_permission('department_management')
)
with check (
  public.current_app_user_is_admin()
  or public.current_app_user_has_mobile_permission('department_management')
);

create policy "Users can read vendors for inventory features"
on public.vendors
for select
to authenticated
using (public.current_app_user_can_view_inventory());

create policy "Users can manage vendors"
on public.vendors
for all
to authenticated
using (
  public.current_app_user_is_admin()
  or public.current_app_user_has_mobile_permission('vendor_management')
)
with check (
  public.current_app_user_is_admin()
  or public.current_app_user_has_mobile_permission('vendor_management')
);

create policy "Users can read product barcodes for inventory features"
on public.product_barcodes
for select
to authenticated
using (public.current_app_user_can_view_inventory());

create policy "Users can insert product barcodes for editable products"
on public.product_barcodes
for insert
to authenticated
with check (public.current_app_user_can_manage_product_catalog());

create policy "Users can delete product barcodes for editable products"
on public.product_barcodes
for delete
to authenticated
using (public.current_app_user_can_manage_product_catalog());

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

create policy "Users can read sales at allowed stores"
on public.sales
for select
to authenticated
using (public.current_app_user_can_view_sales_at_location(location_id));

create policy "Users can insert sales at allowed stores"
on public.sales
for insert
to authenticated
with check (
  user_id = public.current_app_user_id()
  and public.current_app_user_can_sell_at_location(location_id)
);

create policy "Users can read sale items for allowed sales"
on public.sale_items
for select
to authenticated
using (
  exists (
    select 1
    from public.sales s
    where s.sale_id = sale_items.sale_id
      and public.current_app_user_can_view_sales_at_location(s.location_id)
  )
);

create policy "Users can insert sale items for allowed sales"
on public.sale_items
for insert
to authenticated
with check (
  exists (
    select 1
    from public.sales s
    where s.sale_id = sale_items.sale_id
      and s.user_id = public.current_app_user_id()
      and public.current_app_user_can_sell_at_location(s.location_id)
  )
);

create policy "Users can read store transfers they can access"
on public.store_transfers
for select
to authenticated
using (
  public.current_app_user_can_view_store_transfer(from_location_id, to_location_id)
);

create policy "Users can create store transfers between assigned stores"
on public.store_transfers
for insert
to authenticated
with check (
  coalesce(user_id, public.current_app_user_id()) = public.current_app_user_id()
  and public.current_app_user_can_create_store_transfer(from_location_id, to_location_id)
);

create policy "Users can receive destination store transfers"
on public.store_transfers
for update
to authenticated
using (
  public.current_app_user_can_receive_store_transfer(to_location_id)
)
with check (
  public.current_app_user_can_receive_store_transfer(to_location_id)
  and (
    received_by_user_id is null
    or received_by_user_id = public.current_app_user_id()
  )
);

create policy "Users can read transfer items for visible transfers"
on public.store_transfer_items
for select
to authenticated
using (
  exists (
    select 1
    from public.store_transfers st
    where st.transfer_id = store_transfer_items.transfer_id
      and public.current_app_user_can_view_store_transfer(st.from_location_id, st.to_location_id)
  )
);

create policy "Users can insert transfer items for owned transfers"
on public.store_transfer_items
for insert
to authenticated
with check (
  exists (
    select 1
    from public.store_transfers st
    where st.transfer_id = store_transfer_items.transfer_id
      and coalesce(st.user_id, public.current_app_user_id()) = public.current_app_user_id()
      and public.current_app_user_can_create_store_transfer(st.from_location_id, st.to_location_id)
  )
);

create policy "Users can verify transfer item quantities during receive"
on public.store_transfer_items
for update
to authenticated
using (
  exists (
    select 1
    from public.store_transfers st
    where st.transfer_id = store_transfer_items.transfer_id
      and st.status = 'PENDING'
      and public.current_app_user_can_verify_store_transfer_quantity(st.to_location_id)
  )
)
with check (
  quantity > 0
  and exists (
    select 1
    from public.store_transfers st
    where st.transfer_id = store_transfer_items.transfer_id
      and st.status = 'PENDING'
      and public.current_app_user_can_verify_store_transfer_quantity(st.to_location_id)
  )
);

commit;
