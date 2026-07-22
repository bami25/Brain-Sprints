-- Mart: usage event fact. Excludes probable duplicates; flags usage that
-- occurs after trial end for never-converted customers (a data-quality /
-- unmonetised-access signal that should be zero by product rules).
with usage as (
    select * from {{ ref('stg_usage_events') }}
    where not is_probable_duplicate
),
trials as (
    select * from {{ ref('int_trial_periods') }}
),
conversions as (
    select company_id from {{ ref('int_conversions') }}
)

select
    u.usage_id,
    u.company_id,
    u.usage_at,
    cast(u.usage_at as date)          as usage_date,
    date_trunc('month', u.usage_at)   as usage_month,
    u.credit_amount,
    u.usage_category,
    u.usage_subcategory,
    u.user_count_in_event,
    u.seat_count_at_time,
    u.academic_period,
    u.source_system,
    (cv.company_id is null
        and u.usage_at > t.trial_end_date + interval 1 day)
                                      as is_post_trial_unconverted_usage
from usage u
left join trials t        using (company_id)
left join conversions cv  using (company_id)
