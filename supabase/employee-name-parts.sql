-- Maintain employee name parts and full_name.
--
-- Run this after adding first_name, middle_name, and last_name to public.users.
-- It is safe to run even if you already added the columns.

begin;

alter table public.users
add column if not exists first_name text,
add column if not exists middle_name text,
add column if not exists last_name text;

create or replace function public.compose_employee_full_name(
  first_name text,
  middle_name text,
  last_name text
)
returns text
language sql
immutable
as $$
  select btrim(concat_ws(
    ' ',
    nullif(btrim(first_name), ''),
    nullif(btrim(middle_name), ''),
    nullif(btrim(last_name), '')
  ))
$$;

create or replace function public.sync_employee_full_name()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.first_name := nullif(btrim(new.first_name), '');
  new.middle_name := nullif(btrim(new.middle_name), '');
  new.last_name := nullif(btrim(new.last_name), '');

  if new.first_name is not null or new.middle_name is not null or new.last_name is not null then
    new.full_name := public.compose_employee_full_name(new.first_name, new.middle_name, new.last_name);
  else
    new.full_name := nullif(btrim(new.full_name), '');
  end if;

  return new;
end;
$$;

drop trigger if exists sync_employee_full_name_before_insert_or_update on public.users;
create trigger sync_employee_full_name_before_insert_or_update
before insert or update of first_name, middle_name, last_name, full_name on public.users
for each row
execute function public.sync_employee_full_name();

with name_parts as (
  select
    user_id,
    regexp_split_to_array(btrim(full_name), '\s+') as parts
  from public.users
  where (first_name is null or btrim(first_name) = '')
    and (last_name is null or btrim(last_name) = '')
    and full_name is not null
    and btrim(full_name) <> ''
)
update public.users u
set
  first_name = np.parts[1],
  middle_name = case
    when array_length(np.parts, 1) > 2
      then array_to_string(np.parts[2:array_length(np.parts, 1) - 1], ' ')
    else null
  end,
  last_name = case
    when array_length(np.parts, 1) > 1
      then np.parts[array_length(np.parts, 1)]
    else u.last_name
  end
from name_parts np
where u.user_id = np.user_id;

update public.users
set full_name = public.compose_employee_full_name(first_name, middle_name, last_name)
where first_name is not null
  and last_name is not null;

revoke all on function public.compose_employee_full_name(text, text, text) from public;
revoke all on function public.sync_employee_full_name() from public;

commit;
