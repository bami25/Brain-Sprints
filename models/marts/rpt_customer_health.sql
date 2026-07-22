-- Mart: per-customer health summary for currently active accounts.
-- Grain: one row per active, past-due, or paused customer.
-- Purpose: provide CS with a consolidated view of engagement recency,
-- sustained engagement risk, payment risk, and validated expansion signals.

with customers as (

    select *
    from {{ ref('dim_customers') }}

    where subscription_status in (
        'active',
        'past_due',
        'paused'
    )

),

usage_180d as (

    select
        company_id,

        count(*) as events_180d,

        sum(credit_amount) as credits_180d,

        max(usage_at) as last_usage_at,

        max(user_count_in_event) as max_concurrent_users_180d

    from {{ ref('fct_usage_events') }}

    where usage_at >=
        cast('{{ var("as_of_date") }}' as date)
        - interval 180 day

    group by 1

),

churn_signals as (

    select
        company_id,
        events_per_month,
        engagement_band

    from {{ ref('rpt_churn_signals') }}

),

expansion_signals as (

    select
        company_id,
        seat_utilisation_30d,
        events_30d,
        active_days_30d,
        flag_expansion_ready

    from {{ ref('rpt_expansion_candidates') }}

)

select
    c.company_id,
    c.company_name,
    c.industry,
    c.sales_channel,
    c.subscription_status,

    c.current_plan_name,
    c.current_seat_count,
    c.current_mrr,
    c.current_billing_period,

    c.customer_success_owner,

    coalesce(
        u.events_180d,
        0
    ) as events_180d,

    round(
        coalesce(u.credits_180d, 0),
        1
    ) as credits_180d,

    u.last_usage_at,

    datediff(
        'day',
        cast(u.last_usage_at as date),
        cast('{{ var("as_of_date") }}' as date)
    ) as days_since_last_usage,

    round(
        coalesce(u.max_concurrent_users_180d, 0)
        / nullif(c.current_seat_count, 0),
        3
    ) as peak_user_utilisation_180d,

    -- Simple operational flag for accounts with no recent activity.
    (
        coalesce(u.events_180d, 0) = 0

        or datediff(
            'day',
            cast(u.last_usage_at as date),
            cast('{{ var("as_of_date") }}' as date)
        ) > 60
    ) as flag_no_recent_engagement,

    -- Sustained engagement signal validated against voluntary churn.
    ch.events_per_month,
    ch.engagement_band,

    ch.engagement_band = '<2'
        as flag_low_sustained_engagement,

    -- Direct revenue-risk signal.
    c.subscription_status = 'past_due'
        as flag_past_due,

    -- Validated expansion opportunity signal.
    ex.seat_utilisation_30d,
    ex.events_30d,
    ex.active_days_30d,

    coalesce(
        ex.flag_expansion_ready,
        false
    ) as flag_expansion_ready

from customers c

left join usage_180d u
    using (company_id)

left join churn_signals ch
    using (company_id)

left join expansion_signals ex
    using (company_id)