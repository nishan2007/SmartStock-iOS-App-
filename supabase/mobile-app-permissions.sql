-- Mobile-only permissions for the SmartStock iOS app.
--
-- This is intentionally separate from any Java/desktop app permission tables.
-- Run in the Supabase SQL Editor.

begin;

create table if not exists public.mobile_permissions (
  permission_key text primary key,
  display_name text not null,
  permission_group text not null,
  sort_order int not null default 0
);

create table if not exists public.role_mobile_permissions (
  role_id int not null references public.roles(role_id) on delete cascade,
  permission_key text not null references public.mobile_permissions(permission_key) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_key)
);

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

revoke all on function public.current_app_user_role_id() from public;
revoke all on function public.current_app_user_is_admin() from public;
grant execute on function public.current_app_user_role_id() to authenticated;
grant execute on function public.current_app_user_is_admin() to authenticated;

insert into public.mobile_permissions (permission_key, display_name, permission_group, sort_order)
values
  ('adjust_inventory_quantity', 'Adjust Inventory Quantity', 'Inventory', 125),
  ('apply_sale_discount', 'Apply Sale Discount', 'Sales', 15),
  ('change_sale_item_price', 'Change Sale Item Price', 'Sales', 16),
  ('change_store', 'Change Store', 'Operations', 210),
  ('company_preferences', 'Company Preferences', 'Admin', 320),
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
  ('custom_order_deposit_settings', 'Custom Order Deposit Settings', 'Admin', 321),
  ('custom_order_refund_approval_settings', 'Custom Order Refund Approval Settings', 'Admin', 322),
  ('make_sale', 'Make Sale', 'Sales', 10),
  ('view_sales', 'View Previous Transactions', 'Sales', 20),
  ('returns', 'Process Returns', 'Sales', 30),
  ('end_of_day', 'End of Day', 'Sales', 40),
  ('customers', 'Customer Accounts', 'Sales', 50),
  ('manage_customers', 'Manage Customers', 'Sales', 60),
  ('edit_account_number', 'Edit Account Number', 'Sales', 65),
  ('edit_customer_credit_limit', 'Set Credit Limit', 'Sales', 70),
  ('department_management', 'Department Management', 'Inventory', 145),
  ('custom_order_items', 'Custom Order Items', 'Inventory', 146),
  ('custom_order_print_materials', 'Custom Order Print Materials', 'Inventory', 147),
  ('device_management', 'Device Management', 'Device', 300),
  ('device_receipt_settings', 'Local Device Settings', 'Device', 305),
  ('inventory', 'View Inventory List', 'Inventory', 100),
  ('view_all_stores_inventory', 'View All Stores Inventory', 'Inventory', 105),
  ('receiving', 'Receiving Inventory', 'Inventory', 110),
  ('store_transfer', 'Store Transfer', 'Inventory', 120),
  ('verify_store_transfer_quantity', 'Verify Store Transfer Quantity', 'Inventory', 121),
  ('edit_item', 'Edit Item', 'Inventory', 130),
  ('new_item', 'Add New Item', 'Inventory', 140),
  ('hardware_setup', 'Hardware Setup', 'Device', 310),
  ('location_management', 'Location Management', 'Admin', 325),
  ('time_clock', 'Time Clock', 'Employee', 200),
  ('payroll_dashboard', 'Payroll Dashboard', 'Admin', 330),
  ('employees', 'Employee Management', 'Admin', 300),
  ('role_permissions', 'Role Management', 'Admin', 310)
  ,('vendor_management', 'Vendor Management', 'Inventory', 150)
  ,('view_cost_price', 'View Cost Price', 'Inventory', 115)
  ,('view_created_by', 'View Created By', 'Inventory', 116)
  ,('view_item_details', 'View Item Details', 'Inventory', 117)
  ,('view_receiving_history', 'View Receiving History', 'Inventory', 118)
  ,('view_reports', 'View Reports', 'Admin', 335)
  ,('view_vendor', 'View Vendor', 'Inventory', 119)
  ,('maintenance_management', 'Maintenance Management', 'Inventory', 160)
  ,('machine_management', 'Machine Management', 'Inventory', 170)
  ,('parts_management', 'Parts Management', 'Inventory', 180)
on conflict (permission_key) do update
set
  display_name = excluded.display_name,
  permission_group = excluded.permission_group,
  sort_order = excluded.sort_order;

-- Admin role gets every mobile permission by default.
insert into public.role_mobile_permissions (role_id, permission_key)
select 1, permission_key
from public.mobile_permissions
on conflict (role_id, permission_key) do nothing;

alter table public.mobile_permissions enable row level security;
alter table public.role_mobile_permissions enable row level security;

drop policy if exists "Authenticated users can read mobile permissions" on public.mobile_permissions;
drop policy if exists "Users can read their role mobile permissions" on public.role_mobile_permissions;
drop policy if exists "Admins can read all role mobile permissions" on public.role_mobile_permissions;
drop policy if exists "Admins can insert role mobile permissions" on public.role_mobile_permissions;
drop policy if exists "Admins can delete role mobile permissions" on public.role_mobile_permissions;

create policy "Authenticated users can read mobile permissions"
on public.mobile_permissions
for select
to authenticated
using (true);

create policy "Users can read their role mobile permissions"
on public.role_mobile_permissions
for select
to authenticated
using (role_id = public.current_app_user_role_id());

create policy "Admins can read all role mobile permissions"
on public.role_mobile_permissions
for select
to authenticated
using (public.current_app_user_is_admin());

create policy "Admins can insert role mobile permissions"
on public.role_mobile_permissions
for insert
to authenticated
with check (public.current_app_user_is_admin());

create policy "Admins can delete role mobile permissions"
on public.role_mobile_permissions
for delete
to authenticated
using (public.current_app_user_is_admin());

commit;
