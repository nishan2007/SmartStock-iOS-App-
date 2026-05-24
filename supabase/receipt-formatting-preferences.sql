alter table public.company_customization
add column if not exists company_name text not null default 'SmartStock',
add column if not exists receipt_logo_url text not null default '',
add column if not exists receipt_header_line text not null default '',
add column if not exists receipt_footer_line text not null default 'Thank you',
add column if not exists show_receipt_logo boolean not null default true,
add column if not exists show_sale_id_on_receipt boolean not null default true,
add column if not exists show_device_id_on_receipt boolean not null default true,
add column if not exists show_customer_on_receipt boolean not null default true,
add column if not exists show_sku_on_receipt boolean not null default true,
add column if not exists show_item_discounts_on_receipt boolean not null default true,
add column if not exists show_payment_status_on_receipt boolean not null default true;
