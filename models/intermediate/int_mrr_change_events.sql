-- Normalised MRR "state change" events per company:
-- conversion / reactivation / upgrade / downgrade set a new MRR level,
-- churn sets it to zero. Used to build the monthly MRR spine.
with events as (
    select * from {{ ref('stg_subscription_events') }}
)

select
    company_id,
    coalesce(subscription_start_date, cast(created_at as date)) as effective_date,
    monthly_recurring_revenue_gbp                               as new_mrr,
    event_type
from events
where event_type in ('converted', 'reactivation', 'upgrade', 'downgrade')

union all

select
    company_id,
    coalesce(sub_end_date, cast(created_at as date))            as effective_date,
    0                                                           as new_mrr,
    event_type
from events
where event_type in ('voluntary_churn', 'delinquent_churn')
