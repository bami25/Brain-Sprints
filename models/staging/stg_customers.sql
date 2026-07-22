-- Staging: customers
-- One row per customer organisation. Cleans casing inconsistencies and types dates.
with source as (

    select * from {{ source('raw', 'customer_data') }}

),

cleaned as (

    select
        company_id,
        company_name,

        -- ~20 rows arrive with inconsistent casing (SCHOOL / school / School);
        -- normalise to title case so segment reporting doesn't fragment
        {{ title_case("industry") }}                        as industry,

        nullif(trim(region), '')                       as region,
        cast(trial_start_date as date)                 as trial_start_date,
        lower(trim(subscription_status))               as subscription_status,

        -- plan names also carry casing noise (SMALL / medium / 'Small ')
        {{ title_case("current_plan_name") }}               as current_plan_name,

        current_seat_count,
        organisation_size_band,
        lower(trim(sales_channel))                     as sales_channel,
        nullif(trim(customer_success_owner), '')       as customer_success_owner,
        customer_success_owner is not null
            and trim(customer_success_owner) != ''     as has_cs_owner,
        cast(created_at as timestamp)                  as created_at,
        cast(updated_at as timestamp)                  as updated_at

    from source

)

select * from cleaned
