-- Expansion candidates.
-- Grain: one row per currently active converted organisation.
-- Expansion readiness = approaching plan seat capacity while actively
-- using the product, excluding customers who have already upgraded.
-- Plan seat caps: Small 100, Medium 500, Large 1,000; Bespoke is
-- uncapped and therefore never capacity-flagged.

with customers as (

    select
        company_id,
        company_name,
        industry,
        sales_channel,
        current_plan_name,
        current_seat_count,
        current_mrr,
        current_billing_period,
        subscription_status

    from {{ ref('dim_customers') }}

    where subscription_status in ('active', 'past_due', 'paused')
      and ever_converted

),

plan_caps as (

    select
        *,

        case current_plan_name
            when 'Small'  then 100
            when 'Medium' then 500
            when 'Large'  then 1000
        end as plan_seat_cap

    from customers

),

usage_30d as (

    select
        company_id,

        count(*) as events_30d,

        count(
            distinct cast(usage_at as date)
        ) as active_days_30d,

        sum(credit_amount) as credits_30d,

        max(user_count_in_event) as max_concurrent_users_30d

    from {{ ref('fct_usage_events') }}

    where cast(usage_at as date)
          > cast('{{ var("as_of_date") }}' as date) - 30

      and cast(usage_at as date)
          <= cast('{{ var("as_of_date") }}' as date)

    group by 1

),

upgrade_history as (

    select
        company_id,

        count(*) filter (
            where event_type = 'upgrade'
        ) as previous_upgrades

    from {{ ref('fct_subscription_events') }}

    group by 1

)

select
    c.company_id,
    c.company_name,
    c.industry,
    c.sales_channel,

    c.current_plan_name,
    c.current_billing_period,
    c.current_seat_count,
    c.plan_seat_cap,
    c.current_mrr,

    -- how close the account's purchased seats sit to its plan's ceiling
    round(
        c.current_seat_count
        / nullif(c.plan_seat_cap, 0),
        3
    ) as plan_capacity_utilisation,

    coalesce(u.events_30d, 0) as events_30d,

    coalesce(
        u.active_days_30d,
        0
    ) as active_days_30d,

    round(
        coalesce(u.credits_30d, 0),
        1
    ) as credits_30d,

    coalesce(
        u.max_concurrent_users_30d,
        0
    ) as max_concurrent_users_30d,

    -- peak concurrent users vs seats owned (intensity, not capacity)
    round(
        coalesce(u.max_concurrent_users_30d, 0)
        / nullif(c.current_seat_count, 0),
        3
    ) as seat_utilisation_30d,

    coalesce(
        uh.previous_upgrades,
        0
    ) as previous_upgrades,

    (
        coalesce(
            c.current_seat_count
                / nullif(c.plan_seat_cap, 0) >= 0.90,
            false
        )

        and coalesce(u.events_30d, 0) >= 5

        and coalesce(u.active_days_30d, 0) >= 3

        and coalesce(uh.previous_upgrades, 0) = 0

    ) as flag_expansion_ready

from plan_caps c

left join usage_30d u
    using (company_id)

left join upgrade_history uh
    using (company_id)