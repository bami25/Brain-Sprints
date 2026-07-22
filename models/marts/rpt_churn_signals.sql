-- Mart: engagement and voluntary churn signals.
-- Grain: one row per ever-converted organisation.
-- Measures post-conversion engagement over the customer's subscribed period
-- and captures the cancellation-to-churn window for voluntary churners.

with converted as (

    select
        company_id,
        first_paid_date,
        has_churned,
        churn_type,
        churn_date

    from {{ ref('dim_customers') }}

    where ever_converted

),

tenure as (

    select
        company_id,

        greatest(
            1,
            date_diff(
                'month',
                first_paid_date,
                coalesce(
                    churn_date,
                    cast('{{ var("as_of_date") }}' as date)
                )
            ) + 1
        ) as months_subscribed

    from converted

),

post_conversion_usage as (

    select
        u.company_id,

        count(*) as events_post_conversion,

        count(
            distinct cast(u.usage_at as date)
        ) as active_days_post_conversion

    from {{ ref('fct_usage_events') }} u

    join converted c
        using (company_id)

    where cast(u.usage_at as date) >= c.first_paid_date

      and cast(u.usage_at as date) <= coalesce(
            c.churn_date,
            cast('{{ var("as_of_date") }}' as date)
          )

    group by 1

),

cancellations as (

    select
        c.company_id,

        max(
            cast(se.created_at as date)
        ) as cancellation_scheduled_date

    from converted c

    join {{ ref('fct_subscription_events') }} se
        on c.company_id = se.company_id

    where se.event_type = 'cancellation_scheduled'

      and (
          c.churn_date is null
          or cast(se.created_at as date) <= c.churn_date
      )

    group by 1

)

select
    c.company_id,
    c.first_paid_date,

    t.months_subscribed,

    coalesce(
        u.events_post_conversion,
        0
    ) as events_post_conversion,

    coalesce(
        u.active_days_post_conversion,
        0
    ) as active_days_post_conversion,

    round(
        coalesce(u.events_post_conversion, 0)
        / t.months_subscribed,
        2
    ) as events_per_month,

    case
        when coalesce(u.events_post_conversion, 0)
             / t.months_subscribed < 2
            then '<2'

        when coalesce(u.events_post_conversion, 0)
             / t.months_subscribed < 4
            then '2-3.9'

        when coalesce(u.events_post_conversion, 0)
             / t.months_subscribed < 6
            then '4-5.9'

        else '6+'

    end as engagement_band,

    c.has_churned,
    c.churn_type,

    coalesce(
        c.has_churned and c.churn_type = 'voluntary_churn',
        false
    ) as is_voluntary_churn,

    c.churn_date,

    x.cancellation_scheduled_date,

    case
        when c.churn_type = 'voluntary_churn'
         and x.cancellation_scheduled_date is not null
            then c.churn_date - x.cancellation_scheduled_date
    end as days_cancellation_to_churn

from converted c

join tenure t
    using (company_id)

left join post_conversion_usage u
    using (company_id)

left join cancellations x
    using (company_id)