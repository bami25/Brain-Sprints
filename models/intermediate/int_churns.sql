-- One row per company churn event (voluntary or delinquent), latest per company.
select
    company_id,
    event_type                                       as churn_type,
    coalesce(sub_end_date, cast(created_at as date)) as churn_date,
    monthly_recurring_revenue_gbp                    as mrr_at_churn
from {{ ref('stg_subscription_events') }}
where event_type in ('voluntary_churn', 'delinquent_churn')
qualify row_number() over (partition by company_id order by created_at desc) = 1
