-- Trial-window usage per company: events and credits inside the 7-day trial.
with usage as (
    select * from {{ ref('stg_usage_events') }}
    where not is_probable_duplicate
),
trials as (
    select * from {{ ref('int_trial_periods') }}
)

select
    t.company_id,
    count(u.usage_id)                          as trial_usage_events,
    round(coalesce(sum(u.credit_amount), 0), 1) as trial_credits,
    count(distinct u.usage_category)     as trial_categories_touched
from trials t
left join usage u
    on u.company_id = t.company_id
   and u.usage_at >= date_trunc('day', t.trial_started_at)  -- inclusive of trial start day
   and u.usage_at <= t.trial_end_date + interval 1 day      -- inclusive of trial end day
group by 1
