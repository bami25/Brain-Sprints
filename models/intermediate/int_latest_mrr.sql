-- Current MRR per company = most recent MRR-bearing event.
select
    company_id,
    monthly_recurring_revenue_gbp as current_mrr,
    billing_period                as current_billing_period,
    plan_name                     as latest_billed_plan,
    cast(created_at as date)      as mrr_as_of_date
from {{ ref('stg_subscription_events') }}
where event_type in ('converted', 'renewal', 'upgrade', 'downgrade', 'reactivation')
qualify row_number() over (partition by company_id order by created_at desc) = 1
