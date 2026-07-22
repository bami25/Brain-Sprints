with spine as (
    select
        last_day(cast(d as date))                as month_end
    from generate_series(
        date '2023-07-01',
        cast('{{ var("as_of_date") }}' as date),
        interval 1 month
    ) as t(d)
),
changes as (
    select * from {{ ref('int_mrr_change_events') }}
),
state_at_month as (
    select
        s.month_end,
        c.company_id,
        c.new_mrr
    from spine s
    join changes c
      on c.effective_date <= s.month_end
    qualify row_number() over (
        partition by s.month_end, c.company_id
        order by c.effective_date desc, (c.new_mrr = 0) desc
    ) = 1
)

select
    month_end,
    sum(new_mrr)                                   as mrr,
    count(*) filter (where new_mrr > 0)            as active_customers,
    round(sum(new_mrr) / nullif(count(*) filter (where new_mrr > 0), 0), 0)
                                                   as arpa
from state_at_month
group by 1
order by 1
