with customers as (
    select * from {{ ref('stg_customers') }}
),
trials as (
    select * from {{ ref('int_trial_periods') }}
),
conversions as (
    select * from {{ ref('int_conversions') }}
),
churns as (
    select * from {{ ref('int_churns') }}
),
trial_usage as (
    select * from {{ ref('int_trial_usage') }}
),
latest_mrr as (
    select * from {{ ref('int_latest_mrr') }}
)

select
    c.company_id,
    c.company_name,
    c.industry,
    c.region,
    c.organisation_size_band,
    c.sales_channel,
    c.customer_success_owner,
    c.has_cs_owner,
    c.subscription_status,
    c.current_plan_name,
    c.current_seat_count,
    c.trial_start_date,
    t.trial_end_date,

    tu.trial_usage_events,
    tu.trial_credits,
    tu.trial_categories_touched,

    cv.company_id is not null                 as ever_converted,
    cv.first_paid_date,
    cv.first_paid_plan,
    cv.first_billing_period,
    datediff('day', c.trial_start_date, cv.first_paid_date) as days_to_convert,

    -- has_churned reflects the customer's *current* status snapshot, not just
    -- "a churn event exists": a churn followed by a later reactivation event
    -- (see stg_subscription_events event_type='reactivation') must not still
    -- report as churned with zero MRR.
    c.subscription_status in ('voluntary_churn', 'delinquent_churn')
                                              as has_churned,
    ch.churn_type,
    ch.churn_date,
    case when c.subscription_status in ('voluntary_churn', 'delinquent_churn')
         then round(datediff('day', cv.first_paid_date, ch.churn_date) / 30.44, 1)
    end                                       as tenure_months_at_churn,

    case when cv.company_id is not null
          and c.subscription_status not in ('voluntary_churn', 'delinquent_churn')
         then m.current_mrr else 0 end        as current_mrr,
    m.current_billing_period

from customers c
left join trials       t  using (company_id)
left join conversions  cv using (company_id)
left join churns       ch using (company_id)
left join trial_usage  tu using (company_id)
left join latest_mrr   m  using (company_id)
