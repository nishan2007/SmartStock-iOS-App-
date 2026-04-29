-- Salary employees are paid by salary amount, not by per-session earned time.
-- Daily employees are paid once per worked day, not once per clock session.

begin;

update public.employee_time_clock etc
set total_earned = null
from public.users u
where u.user_id = etc.user_id
  and upper(btrim(u.compensation_type::text)) in ('SALARY', 'SALARIED', 'SALARY EMPLOYEE', 'SALARIED EMPLOYEE')
  and etc.total_earned is not null;

with ranked_daily_sessions as (
  select
    etc.clock_id,
    row_number() over (
      partition by etc.user_id, date(etc.clock_in)
      order by etc.clock_in, etc.clock_id
    ) as daily_session_number
  from public.employee_time_clock etc
  join public.users u on u.user_id = etc.user_id
  where upper(btrim(u.compensation_type::text)) in ('DAILY', 'DAY', 'DAY RATE', 'DAILY EMPLOYEE')
    and etc.clock_out is not null
    and etc.total_earned is not null
)
update public.employee_time_clock etc
set total_earned = null
from ranked_daily_sessions ranked
where ranked.clock_id = etc.clock_id
  and ranked.daily_session_number > 1;

comment on column public.employee_time_clock.total_earned is
  'Rounded earned amount for completed clock session. Null for salary employees; daily employees should only have one earned amount per worked day.';

comment on column public.users.salary is
  'Unified compensation amount. Interpret with compensation_type: hourly rate, daily rate, or salary pay amount.';

commit;
