-- One row per company: trial window boundaries.
select
    company_id,
    created_at              as trial_started_at,
    trial_end_date
from {{ ref('stg_subscription_events') }}
where event_type = 'trial_start'
