-- Staging: subscription events
-- One row per lifecycle / payment event. Cleans plan casing, types dates,
-- derives payment timing, and normalises revenue to GBP for portfolio rollups.
with source as (

    select * from {{ source('raw', 'subscription_events') }}

),

cleaned as (

    select
        subscription_event_id,
        company_id,
        lower(trim(event_type))                          as event_type,
        {{ title_case("plan_name") }}                         as plan_name,
        {{ title_case("previous_plan_name") }}                as previous_plan_name,
        cast(payment_date as date)                       as payment_date,
        cast(subscription_start_date as date)            as subscription_start_date,
        cast(sub_end_date as date)                       as sub_end_date,
        cast(trial_end_date as date)                     as trial_end_date,
        lower(trim(billing_period))                      as billing_period,
        seat_count,
        monthly_recurring_revenue,
        invoice_amount,
        upper(trim(currency))                            as currency,
        lower(trim(payment_status))                      as payment_status,
        cast(created_at as timestamp)                    as created_at,

    from source

),

converted_currency as (

    select
        *,

        -- Normalise monetary fields to GBP so portfolio-level rollups (MRR,
        -- ARPA) don't silently sum GBP and EUR figures as if equivalent.
        -- ~82 EUR rows exist (mostly Ireland); single-currency-per-customer
        -- is enforced separately in tests/assert_single_currency_per_customer.
        case when currency = 'EUR'
             then round(monthly_recurring_revenue * {{ var('eur_gbp_rate') }}, 2)
             else monthly_recurring_revenue
        end as monthly_recurring_revenue_gbp,

        case when currency = 'EUR'
             then round(invoice_amount * {{ var('eur_gbp_rate') }}, 2)
             else invoice_amount
        end as invoice_amount_gbp

    from cleaned

)

select * from converted_currency
