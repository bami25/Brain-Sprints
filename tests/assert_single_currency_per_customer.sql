-- Customers should be billed in one currency; mixed-currency accounts break
-- naive GBP MRR aggregation (82 EUR rows exist, mostly Ireland).
{{ config(severity='warn') }}

select company_id, count(distinct currency) as currencies
from {{ ref('fct_subscription_events') }}
where currency is not null
group by 1
having count(distinct currency) > 1
