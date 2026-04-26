-- Allows the mobile app to load role names for employee forms and role permissions.
-- Run in the Supabase SQL Editor.

begin;

alter table public.roles enable row level security;

drop policy if exists "Authenticated users can read roles" on public.roles;

create policy "Authenticated users can read roles"
on public.roles
for select
to authenticated
using (true);

commit;
