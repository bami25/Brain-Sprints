{% macro title_case(col) -%}
    {# DuckDB has no initcap; title-case each word portably #}
    list_aggregate(
        list_transform(
            string_split(lower(trim({{ col }})), ' '),
            x -> upper(x[1]) || x[2:]
        ),
        'string_agg', ' '
    )
{%- endmacro %}
