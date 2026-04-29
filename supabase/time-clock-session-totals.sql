begin;

-- USERS: keep compensation_type + one unified salary amount.
alter table public.users
  add column if not exists salary numeric(12, 2);

update public.users
set salary = case compensation_type::text
  when 'SALARY' then nullif(salary_amount, 0)
  when 'HOURLY' then nullif(hourly_wage, 0)
  when 'DAILY' then nullif(daily_salary, 0)
  else salary
end
where salary is null;

update public.users
set salary = coalesce(
  salary,
  nullif(salary_amount, 0),
  nullif(hourly_wage, 0),
  nullif(daily_salary, 0),
  0
)
where salary is null;

alter table public.users
  drop column if exists hourly_wage,
  drop column if exists salary_amount,
  drop column if exists daily_salary;

comment on column public.users.salary is
  'Unified compensation amount. Interpret with compensation_type: hourly rate, daily rate, or salary amount.';

-- TIME CLOCK: keep only punch/session data and stored session totals.
alter table public.employee_time_clock
  add column if not exists total_hours_worked numeric(10, 2),
  add column if not exists total_earned numeric(12, 2);

update public.employee_time_clock etc
set total_hours_worked = round(
  greatest(
    extract(epoch from (
      coalesce(etc.clock_out, now()) - etc.clock_in
      - case
          when etc.lunch_start is not null then
            greatest(coalesce(etc.lunch_end, coalesce(etc.clock_out, now())) - etc.lunch_start, interval '0 seconds')
          else interval '0 seconds'
        end
    )) / 3600.0,
    0
  )::numeric,
  2
)
where etc.total_hours_worked is null;

update public.employee_time_clock etc
set total_earned = round(
  case u.compensation_type::text
    when 'HOURLY' then coalesce(u.salary, 0) * coalesce(etc.total_hours_worked, 0)
    when 'DAILY' then coalesce(u.salary, 0)
    when 'SALARY' then (coalesce(u.salary, 0) / 2080.0) * coalesce(etc.total_hours_worked, 0)
    else 0
  end::numeric,
  2
)
from public.users u
where u.user_id = etc.user_id
  and etc.clock_out is not null
  and etc.total_earned is null;

alter table public.employee_time_clock
  drop column if exists hourly_wage,
  drop column if exists compensation_type,
  drop column if exists salary_amount,
  drop column if exists daily_salary,
  drop column if exists pay_period_type;

comment on column public.employee_time_clock.total_hours_worked is
  'Rounded hours worked for the completed clock session, excluding lunch.';

comment on column public.employee_time_clock.total_earned is
  'Rounded earned amount for the completed clock session.';

commit;
