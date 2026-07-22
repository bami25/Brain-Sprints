-- Per-trial activation profile.
-- Grain: one row per organisation that started a trial.
-- Activation = activity on 4+ distinct trial days and engagement with
-- all 3 core product categories during the defined 7-day trial window.

with trials as (

    select *
    from {{ ref('int_trial_periods') }}

),

customers as (

    select
        company_id,
        sales_channel,
        has_cs_owner

    from {{ ref('stg_customers') }}

),

conversions as (

    select
        company_id

    from {{ ref('int_conversions') }}

),

trial_usage as (

    select
        t.company_id,

        count(u.usage_id) as trial_usage_events,

        round(
            coalesce(sum(u.credit_amount), 0),
            1
        ) as trial_credits,

        count(
            distinct u.usage_category
        ) as trial_categories_touched,

        count(
            distinct cast(u.usage_at as date)
        ) as trial_active_days

    from trials t

    left join {{ ref('fct_usage_events') }} u
        on u.company_id = t.company_id
        and u.usage_at >= date_trunc('day', t.trial_started_at)
        and u.usage_at < t.trial_end_date + interval 1 day

    group by 1

)

select
    t.company_id,
    c.sales_channel,
    c.has_cs_owner,

    tu.trial_usage_events,
    tu.trial_credits,
    tu.trial_categories_touched,
    tu.trial_active_days,

    case
        when tu.trial_usage_events = 0
            then '0'

        when tu.trial_usage_events <= 3
            then '1-3'

        when tu.trial_usage_events <= 6
            then '4-6'

        when tu.trial_usage_events <= 10
            then '7-10'

        else '11+'

    end as trial_usage_band,

    tu.trial_active_days >= 4
        and tu.trial_categories_touched >= 3
        as is_activated,

    cv.company_id is not null
        as ever_converted

from trials t

join customers c
    using (company_id)

left join trial_usage tu
    using (company_id)

left join conversions cv
    using (company_id)