-- Auto-generate unique employee badge IDs.
--
-- Run this in the Supabase SQL Editor.
-- Badge IDs are identifiers, not secrets. Use a password/PIN/permission check for
-- manager overrides or other sensitive approvals.

begin;

alter table public.users
add column if not exists badge_id text;

create or replace function public.generate_employee_badge_id()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate text;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code_length int := 10;
  i int;
begin
  loop
    candidate := '';

    for i in 1..code_length loop
      candidate := candidate || substr(alphabet, floor(random() * length(alphabet) + 1)::int, 1);
    end loop;

    exit when not exists (
      select 1
      from public.users u
      where upper(btrim(u.badge_id)) = candidate
    );
  end loop;

  return candidate;
end;
$$;

create or replace function public.assign_employee_badge_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.badge_id is null or btrim(new.badge_id) = '' then
    new.badge_id := public.generate_employee_badge_id();
  else
    new.badge_id := upper(regexp_replace(btrim(new.badge_id), '[^a-zA-Z0-9]', '', 'g'));
  end if;

  return new;
end;
$$;

drop trigger if exists assign_employee_badge_id_before_insert_or_update on public.users;
create trigger assign_employee_badge_id_before_insert_or_update
before insert or update of badge_id on public.users
for each row
execute function public.assign_employee_badge_id();

update public.users
set badge_id = public.generate_employee_badge_id()
where badge_id is null or btrim(badge_id) = '';

create unique index if not exists users_badge_id_unique_idx
on public.users (upper(btrim(badge_id)))
where badge_id is not null and btrim(badge_id) <> '';

create or replace function public.lookup_login_user(identifier text)
returns table (
  email text,
  auth_user_id uuid,
  is_active boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select u.email, u.auth_user_id, u.is_active
  from public.users u
  where u.is_active = true
    and (
      lower(u.username) = lower(btrim(identifier))
      or lower(u.email) = lower(btrim(identifier))
      or upper(btrim(u.badge_id)) = upper(regexp_replace(btrim(identifier), '[^a-zA-Z0-9]', '', 'g'))
    )
  limit 1
$$;

revoke all on function public.generate_employee_badge_id() from public;
revoke all on function public.assign_employee_badge_id() from public;
revoke all on function public.lookup_login_user(text) from public;

grant execute on function public.lookup_login_user(text) to anon;
grant execute on function public.lookup_login_user(text) to authenticated;

commit;
