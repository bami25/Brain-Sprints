-- Staging: usage events
-- One row per credit-consuming event. Cleans category casing and flags
-- duplicate-looking events (same company, timestamp, credits, category and
-- user count) so downstream models can exclude them without losing lineage.
with source as (

    select * from {{ source('raw', 'usage_data') }}

),

cleaned as (

    select
        usage_id,
        company_id,
        cast(usage_datetime as timestamp)          as usage_at,
        credit_amount,
        {{ title_case("usage_category") }}              as usage_category,
        nullif(trim(usage_subcategory), '')        as usage_subcategory,
        user_count_in_event,
        seat_count_at_time,
        academic_period,
        lower(trim(source_system))                 as source_system,
        cast(created_at as timestamp)              as created_at

    from source

),

deduped as (

    select
        *,
        row_number() over (
            partition by company_id, usage_at, credit_amount,
                         usage_category, user_count_in_event
            order by created_at, usage_id
        ) as event_instance_number

    from cleaned

)

select
    *,
    event_instance_number > 1 as is_probable_duplicate
from deduped
