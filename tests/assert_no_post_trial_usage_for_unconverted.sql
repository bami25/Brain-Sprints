-- Product rule: never-converted trials must not have usage after trial_end_date.
-- Raw timestamps initially suggested ~120 violating rows (~80 companies), but
-- every one falls within the trial_end calendar day itself a date-vs-timestamp
-- boundary artifact, not real unmonetised access. fct_usage_events treats the
-- trial_end day as inclusive, so this test now passes; it stays in place to
-- catch any *genuine* post-trial usage in future loads.
select *
from {{ ref('fct_usage_events') }}
where is_post_trial_unconverted_usage
