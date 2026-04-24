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
    coalesce(public.current_app_user_is_admin(), false)
    or (
      (
        public.current_app_user_has_mobile_permission('new_item')
        or public.current_app_user_has_mobile_permission('edit_item')
        or public.current_app_user_has_mobile_permission('adjust_inventory_quantity')
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
revoke all on function public.current_app_user_can_view_inventory() from public;
revoke all on function public.current_app_user_can_manage_product_catalog() from public;
revoke all on function public.current_app_user_can_create_products() from public;
revoke all on function public.current_app_user_can_edit_products() from public;
revoke all on function public.current_app_user_can_manage_inventory_for_location(int) from public;

grant execute on function public.current_app_user_id() to authenticated;
grant execute on function public.current_app_user_role_id() to authenticated;
grant execute on function public.current_app_user_is_admin() to authenticated;
grant execute on function public.current_app_user_has_mobile_permission(text) to authenticated;
grant execute on function public.current_app_user_location_ids() to authenticated;
grant execute on function public.current_app_user_can_view_inventory() to authenticated;
grant execute on function public.current_app_user_can_manage_product_catalog() to authenticated;
grant execute on function public.current_app_user_can_create_products() to authenticated;
grant execute on function public.current_app_user_can_edit_products() to authenticated;
grant execute on function public.current_app_user_can_manage_inventory_for_location(int) to authenticated;

alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.categories enable row level security;
alter table public.vendors enable row level security;
alter table public.product_barcodes enable row level security;

drop policy if exists "Users can read products for inventory features" on public.products;
drop policy if exists "Users can create products" on public.products;
drop policy if exists "Users can update products" on public.products;
drop policy if exists "Users can read inventory at allowed stores" on public.inventory;
drop policy if exists "Users can create inventory at allowed stores" on public.inventory;
drop policy if exists "Users can update inventory at allowed stores" on public.inventory;
drop policy if exists "Users can read inventory movements at allowed stores" on public.inventory_movements;
drop policy if exists "Users can insert inventory movements at allowed stores" on public.inventory_movements;
drop policy if exists "Users can read categories for inventory features" on public.categories;
drop policy if exists "Users can manage categories" on public.categories;
drop policy if exists "Users can read vendors for inventory features" on public.vendors;
drop policy if exists "Users can manage vendors" on public.vendors;
drop policy if exists "Users can read product barcodes for inventory features" on public.product_barcodes;
drop policy if exists "Users can insert product barcodes for editable products" on public.product_barcodes;
drop policy if exists "Users can delete product barcodes for editable products" on public.product_barcodes;
drop policy if exists "Users can read product barcodes at assigned stores" on public.product_barcodes;

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
  and (
    public.current_app_user_is_admin()
    or location_id in (
      select location_id
      from public.current_app_user_location_ids()
    )
  )
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
  public.current_app_user_can_view_inventory()
  and (
    public.current_app_user_is_admin()
    or location_id in (
      select location_id
      from public.current_app_user_location_ids()
    )
  )
);

create policy "Users can insert inventory movements at allowed stores"
on public.inventory_movements
for insert
to authenticated
with check (
  public.current_app_user_can_manage_inventory_for_location(location_id)
  and reason in ('NEW_ITEM', 'MANUAL_ADJUSTMENT')
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

commit;
