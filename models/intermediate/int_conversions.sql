-- One row per company that ever converted to paid: first conversion event.
select
    company_id,
    subscription_start_date       as first_paid_date,
    plan_name                     as first_paid_plan,
    billing_period                as first_billing_period,
    monthly_recurring_revenue_gbp as first_mrr,
    seat_count                    as first_paid_seats
from {{ ref('stg_subscription_events') }}
where event_type = 'converted'
qualify row_number() over (partition by company_id order by subscription_start_date) = 1
